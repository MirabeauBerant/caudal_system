//=============================================================================
// auto_calibrator.sv — Módulo de Autocalibración Difusa
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Aplica la señal de corrección del motor difuso al caudal medido
//   para producir un caudal calibrado. Implementa:
//
//   1. Conversión de frecuencia a caudal (L/min × 256 en Q8.8):
//        Q = (freq + 3) * 256 / 7.5
//      Aproximado sin divisor real:
//        Q ≈ (freq + 3) * 34   (donde 256/7.5 ≈ 34.133)
//
//   2. Cálculo de error: ΔQ = Q_setpoint - Q_medido
//
//   3. Aplicación de corrección difusa al caudal:
//        Q_calibrado = Q_medido + correction
//
//   4. Detección de anomalías:
//        - FUGA:   caudal > 0 cuando debería ser 0
//        - ATASCO: caudal = 0 cuando debería ser > 0
//        - BURBUJA: cambios bruscos (|dQ/dt| > umbral)
//
//   5. Generación de señales de estado para LEDs
//
// Parámetros:
//   BUBBLE_THRESHOLD — Umbral de derivada para detección de burbuja
//
// Latencia: 2 ciclos de reloj
// Recursos estimados: ~80 FFs, ~100 LUTs
//=============================================================================

import fuzzy_pkg::*;

module auto_calibrator #(
  parameter int BUBBLE_THRESHOLD = 50,    // Umbral dQ/dt para burbuja
  parameter int FLOW_SCALE       = 34     // ≈ 256/7.5 (factor Q8.8)
)(
  input  logic                            i_clk,
  input  logic                            i_rst_n,

  // Del freq_counter
  input  logic [15:0]                     i_freq,        // Frecuencia medida (Hz)
  input  logic signed [15:0]              i_deriv,       // Derivada de frecuencia
  input  logic                            i_valid,       // Dato nuevo

  // Del fuzzy_controller
  input  logic signed [OUTPUT_WIDTH-1:0]  i_correction,  // Señal de corrección

  // Setpoint de caudal (configurable via switches)
  input  logic [15:0]                     i_setpoint,    // Q deseado (Q8.8 L/min)

  // Salidas
  output logic [15:0]                     o_flow_raw,    // Caudal medido (Q8.8)
  output logic [15:0]                     o_flow_cal,    // Caudal calibrado (Q8.8)
  output logic signed [INPUT_WIDTH-1:0]   o_error,       // Error para feedback
  output logic signed [INPUT_WIDTH-1:0]   o_deriv_out,   // Derivada para feedback
  output logic                            o_valid,

  // Señales de estado
  output logic                            o_status_ok,   // Sistema operando normal
  output logic                            o_status_warn, // Advertencia (deriva alta)
  output logic                            o_status_alert // Alerta (anomalía crítica)
);

  // ── Etapa 1: Conversión frecuencia → caudal y cálculo de error ──
  logic [31:0] w_flow_raw_ext;
  logic [15:0] w_flow_raw;
  logic signed [INPUT_WIDTH-1:0] w_error;
  logic signed [INPUT_WIDTH-1:0] w_deriv;

  always_comb begin
    // Q(L/min × 256) ≈ (freq + 3) × 34
    // Limitamos freq+3 para evitar overflow en 32-bit
    w_flow_raw_ext = (32'(i_freq) + 32'd3) * 32'(FLOW_SCALE);

    // Saturar a 16 bits
    if (w_flow_raw_ext > 32'hFFFF)
      w_flow_raw = 16'hFFFF;
    else
      w_flow_raw = w_flow_raw_ext[15:0];

    // Error = Setpoint - Medido (en Q8.8)
    w_error = $signed({1'b0, i_setpoint}) - $signed({1'b0, w_flow_raw});

    // Derivada: pasar directamente (ya calculada en freq_counter)
    w_deriv = i_deriv;
  end

  // Registros de etapa 1
  logic [15:0]                    r_flow_raw;
  logic signed [INPUT_WIDTH-1:0] r_error;
  logic signed [INPUT_WIDTH-1:0] r_deriv;
  logic                          r_stage1_valid;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_flow_raw     <= '0;
      r_error        <= '0;
      r_deriv        <= '0;
      r_stage1_valid <= 1'b0;
    end
    else begin
      if (i_valid) begin
        r_flow_raw <= w_flow_raw;
        r_error    <= w_error;
        r_deriv    <= w_deriv;
      end
      r_stage1_valid <= i_valid;
    end
  end

  // ── Etapa 2: Aplicar corrección y diagnosticar ──
  logic [15:0] w_flow_cal;
  logic        w_ok, w_warn, w_alert;

  // Señales intermedias (fuera de always_comb para compatibilidad Quartus)
  logic signed [16:0]  w_cal_ext;
  logic signed [15:0]  w_abs_error;
  logic signed [15:0]  w_abs_deriv;

  assign w_cal_ext  = $signed({1'b0, r_flow_raw}) + $signed(i_correction);
  assign w_abs_error = (r_error < 0) ? -r_error : r_error;
  assign w_abs_deriv = (r_deriv < 0) ? -r_deriv : r_deriv;

  always_comb begin
    // Caudal calibrado = medido + corrección
    // Protección contra underflow (caudal no puede ser negativo)
    if (w_cal_ext < 0)
      w_flow_cal = 16'd0;
    else if (w_cal_ext > 17'sd65535)
      w_flow_cal = 16'hFFFF;
    else
      w_flow_cal = w_cal_ext[15:0];

    // ── Diagnóstico de anomalías ──
    w_ok    = 1'b0;
    w_warn  = 1'b0;
    w_alert = 1'b0;

    if (r_flow_raw == '0 && i_setpoint == '0) begin
      // Sin flujo esperado ni medido → todo bien (standby)
      w_ok = 1'b1;
    end
    else if (r_flow_raw == '0 && i_setpoint != '0) begin
      // ATASCO: se espera flujo pero no hay → alerta
      w_alert = 1'b1;
    end
    else if (r_flow_raw != '0 && i_setpoint == '0) begin
      // FUGA: hay flujo pero no se espera → alerta
      w_alert = 1'b1;
    end
    else begin
      // Flujo activo: evaluar magnitud del error y derivada
      if (w_abs_deriv > BUBBLE_THRESHOLD) begin
        // BURBUJA: cambio abrupto → advertencia
        w_warn = 1'b1;
      end
      else if (w_abs_error > 16'sd20) begin
        // Error grande → advertencia
        w_warn = 1'b1;
      end
      else begin
        // Todo normal
        w_ok = 1'b1;
      end
    end
  end

  // Registro de salida (etapa 2)
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_flow_raw    <= '0;
      o_flow_cal    <= '0;
      o_error       <= '0;
      o_deriv_out   <= '0;
      o_valid       <= 1'b0;
      o_status_ok   <= 1'b1;
      o_status_warn <= 1'b0;
      o_status_alert<= 1'b0;
    end
    else begin
      if (r_stage1_valid) begin
        o_flow_raw     <= r_flow_raw;
        o_flow_cal     <= w_flow_cal;
        o_error        <= r_error;
        o_deriv_out    <= r_deriv;
        o_status_ok    <= w_ok;
        o_status_warn  <= w_warn;
        o_status_alert <= w_alert;
      end
      o_valid <= r_stage1_valid;
    end
  end

endmodule : auto_calibrator
