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
//      Optimizado con shifts: (x << 5) + (x << 1) = x*32 + x*2 = x*34
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
//   FLOW_SCALE       — Factor de conversión freq→caudal (≈34 para YF-S201)
//
// Latencia: 2 ciclos de reloj (pipeline de 2 etapas)
// Recursos estimados: ~80 FFs, ~100 LUTs
//=============================================================================

import fuzzy_pkg::*;                      // Importar constantes globales: INPUT_WIDTH, OUTPUT_WIDTH, etc.

module auto_calibrator #(
  parameter int BUBBLE_THRESHOLD = 50,    // Umbral de |dFreq/dt| para detectar burbuja de aire (pulsos/s²)
  parameter int FLOW_SCALE       = 34     // Factor de escala Q8.8: ≈ 256/7.5 según ecuación YF-S201
)(
  input  logic                            i_clk,          // Reloj del sistema (50 MHz)
  input  logic                            i_rst_n,        // Reset asíncrono activo bajo

  // ── Entradas del pipeline de adquisición (freq_counter + EMA) ──
  input  logic [15:0]                     i_freq,         // Frecuencia filtrada del sensor (Hz, unsigned)
  input  logic signed [15:0]              i_deriv,        // Derivada de frecuencia filtrada (Hz/s, signed)
  input  logic                            i_valid,        // Strobe: indica que i_freq e i_deriv son válidos

  // ── Entrada de corrección del controlador difuso (realimentación) ──
  input  logic signed [OUTPUT_WIDTH-1:0]  i_correction,   // Señal de corrección Takagi-Sugeno (signed Q8.8)

  // ── Setpoint de caudal (configurable via switches del panel) ──
  input  logic [15:0]                     i_setpoint,     // Caudal deseado por el usuario (Q8.8 L/min)

  // ── Salidas hacia downstream (display, fuzzy controller, UART) ──
  output logic [15:0]                     o_flow_raw,     // Caudal medido sin corrección (Q8.8 L/min)
  output logic [15:0]                     o_flow_cal,     // Caudal calibrado con corrección difusa (Q8.8)
  output logic signed [INPUT_WIDTH-1:0]   o_error,        // Error de caudal para realimentación al fuzzy
  output logic signed [INPUT_WIDTH-1:0]   o_deriv_out,    // Derivada para realimentación al fuzzy
  output logic                            o_valid,        // Strobe: indica que las salidas son válidas

  // ── Señales de diagnóstico para el módulo led_status ──
  output logic                            o_status_ok,    // Flag: sistema operando normalmente
  output logic                            o_status_warn,  // Flag: advertencia (deriva alta o burbuja)
  output logic                            o_status_alert  // Flag: alerta crítica (fuga o atasco)
);

  // ═══════════════════════════════════════════════════════════════════════
  //  ETAPA 1: Conversión frecuencia → caudal Q8.8 y cálculo de error
  // ═══════════════════════════════════════════════════════════════════════

  logic [19:0] w_freq_plus_3;             // Frecuencia + offset del fabricante (20 bits para evitar overflow)
  logic [19:0] w_flow_raw_ext;            // Resultado extendido de la multiplicación por 34
  logic [15:0] w_flow_raw;                // Caudal bruto saturado a 16 bits (Q8.8 L/min)
  logic signed [INPUT_WIDTH-1:0] w_error; // Error de caudal: setpoint - medido (signed Q8.8)
  logic signed [INPUT_WIDTH-1:0] w_deriv; // Derivada pasada directamente desde el EMA filter

  always_comb begin
    // Ecuación del fabricante YF-S201: F = 7.5·Q − 3 → Q = (F + 3) / 7.5
    // En Q8.8: Q_q88 = (F + 3) × (256 / 7.5) ≈ (F + 3) × 34
    // Optimización: ×34 = (×32) + (×2) = (x<<5) + (x<<1) → elimina multiplicador HW.
    // Se usan 20 bits en lugar de 32 para ahorrar LEs (max freq ≈ 30 kHz cabe en 20 bits).
    w_freq_plus_3  = 20'(i_freq) + 20'd3;              // Aplicar offset +3 del datasheet YF-S201
    w_flow_raw_ext = (w_freq_plus_3 << 5)               // Shift izq. 5 = ×32
                   + (w_freq_plus_3 << 1);              // Shift izq. 1 = ×2  → total ×34

    // Saturar a 16 bits para representación Q8.8 (max = 255.99 L/min).
    // Overflow solo ocurriría con freq > 1927 Hz → imposible con YF-S201 (max ~225 Hz).
    if (w_flow_raw_ext > 20'hFFFF)
      w_flow_raw = 16'hFFFF;                            // Clamp: saturar al máximo representable Q8.8
    else
      w_flow_raw = w_flow_raw_ext[15:0];                // Truncar bits altos (son cero en rango normal)

    // Cálculo de error de lazo cerrado: ΔQ = Q_deseado − Q_medido.
    // Ambos operandos se extienden a signed (17 bits) para aritmética con signo segura.
    w_error = $signed({1'b0, i_setpoint})               // Extender setpoint a signed (siempre positivo)
            - $signed({1'b0, w_flow_raw});              // Extender caudal medido a signed

    // La derivada ya fue calculada y filtrada por el EMA: pasar directamente al pipeline.
    w_deriv = i_deriv;                                  // Reutilizar derivada filtrada del freq_counter
  end

  // ── Registros de pipeline Etapa 1 (captura combinacional → registrada) ──
  logic [15:0]                    r_flow_raw;           // Caudal bruto latched al final de Etapa 1
  logic signed [INPUT_WIDTH-1:0]  r_error;              // Error latched al final de Etapa 1
  logic signed [INPUT_WIDTH-1:0]  r_deriv;              // Derivada latched al final de Etapa 1
  logic                           r_stage1_valid;       // Strobe retardado 1 ciclo (señaliza Etapa 2)

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      // RESET: Limpiar todos los registros de Etapa 1.
      r_flow_raw     <= '0;                             // Caudal bruto a cero
      r_error        <= '0;                             // Error a cero (sin desviación)
      r_deriv        <= '0;                             // Derivada a cero (sin cambio)
      r_stage1_valid <= 1'b0;                           // Sin dato válido pendiente
    end
    else begin
      if (i_valid) begin
        // CAPTURA: Almacenar resultados combinacionales cuando hay dato nuevo del EMA.
        r_flow_raw <= w_flow_raw;                       // Registrar caudal bruto calculado
        r_error    <= w_error;                          // Registrar error de lazo cerrado
        r_deriv    <= w_deriv;                          // Registrar derivada filtrada
      end
      // Propagar strobe de validez con 1 ciclo de latencia (pipeline stage boundary).
      r_stage1_valid <= i_valid;                        // El dato de Etapa 1 estará listo en el próximo ciclo
    end
  end

  // ═══════════════════════════════════════════════════════════════════════
  //  ETAPA 2: Aplicar corrección difusa y diagnosticar anomalías
  // ═══════════════════════════════════════════════════════════════════════

  logic [15:0] w_flow_cal;                              // Caudal calibrado (resultado final Q8.8)
  logic        w_ok, w_warn, w_alert;                   // Flags de diagnóstico combinacionales

  // Señales intermedias declaradas fuera de always_comb para compatibilidad Quartus Prime.
  // Quartus no soporta declaraciones 'automatic' dentro de always_comb en ciertas versiones.
  logic signed [16:0]  w_cal_ext;                       // Resultado extendido a 17 bits para detectar underflow
  logic signed [15:0]  w_abs_error;                     // Valor absoluto del error (para comparación de umbral)
  logic signed [15:0]  w_abs_deriv;                     // Valor absoluto de derivada (para detección de burbuja)

  // Cálculo de caudal corregido: Q_cal = Q_raw + correction_difusa.
  // Se extiende a 17 bits signed para detectar underflow (resultado negativo).
  assign w_cal_ext  = $signed({1'b0, r_flow_raw})       // Extender caudal bruto a 17-bit signed
                    + $signed(i_correction);             // Sumar corrección del controlador difuso T-S

  // Valores absolutos para comparación contra umbrales de diagnóstico.
  assign w_abs_error = (r_error < 0) ? -r_error : r_error;  // |error| para evaluar magnitud de desviación
  assign w_abs_deriv = (r_deriv < 0) ? -r_deriv : r_deriv;  // |derivada| para evaluar cambio brusco

  always_comb begin
    // ── Saturación y Topes del caudal calibrado (Deadband y Clamping) ──
    if (w_cal_ext < 17'sd256) begin
      // DEADBAND: Si el caudal calculado es menor a 1.00 L/min (256 en Q8.8),
      // forzar a 0 para eliminar ruido, goteos o vibraciones.
      w_flow_cal = 16'd0;
    end
    else if (w_cal_ext > 17'sd7680) begin
      // CLAMPING: Si el caudal supera los 30.00 L/min (7680 en Q8.8),
      // limitar a 30.00 L/min ya que el sensor YF-S201 no es fiable más allá.
      w_flow_cal = 16'd7680;
    end
    else begin
      // NORMAL: Rango válido (1.00 a 30.00 L/min)
      w_flow_cal = w_cal_ext[15:0];
    end

    // ── Árbol de diagnóstico de anomalías hidráulicas ──
    // Evalúa 4 condiciones mutuamente excluyentes basadas en flujo y setpoint.
    w_ok    = 1'b0;                                     // Inicializar flags en "no determinado"
    w_warn  = 1'b0;
    w_alert = 1'b0;

    if (r_flow_raw == '0 && i_setpoint == '0) begin
      // STANDBY: No hay flujo esperado ni medido → sistema inactivo, todo bien.
      w_ok = 1'b1;
    end
    else if (r_flow_raw == '0 && i_setpoint != '0) begin
      // ATASCO: Se espera flujo (setpoint > 0) pero el sensor no detecta pulsos.
      // Posible causa: válvula cerrada, tubería obstruida, sensor desconectado.
      w_alert = 1'b1;
    end
    else if (r_flow_raw != '0 && i_setpoint == '0) begin
      // FUGA: Hay flujo medido pero no se espera ninguno (setpoint = 0).
      // Posible causa: válvula con fuga, tubería rota, consumo no autorizado.
      w_alert = 1'b1;
    end
    else begin
      // FLUJO ACTIVO: Tanto setpoint como medición son > 0 → evaluar calidad.
      if (w_abs_deriv > BUBBLE_THRESHOLD) begin
        // BURBUJA: Cambio abrupto en derivada supera umbral → aire en tubería.
        // El sensor YF-S201 genera picos espúreos al pasar burbujas de aire.
        w_warn = 1'b1;
      end
      else if (w_abs_error > 16'sd20) begin
        // ERROR ALTO: La desviación setpoint-medido supera 20 unidades Q8.8.
        // Indica que el sistema de corrección difusa aún no ha convergido.
        w_warn = 1'b1;
      end
      else begin
        // NORMAL: Error bajo y derivada estable → sistema operando correctamente.
        w_ok = 1'b1;
      end
    end
  end

  // ── Registros de pipeline Etapa 2 (salida final del módulo) ──
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      // RESET: Inicializar salidas a valores seguros (sin flujo, sin error, estado OK).
      o_flow_raw     <= '0;                             // Caudal bruto a cero
      o_flow_cal     <= '0;                             // Caudal calibrado a cero
      o_error        <= '0;                             // Error a cero
      o_deriv_out    <= '0;                             // Derivada a cero
      o_valid        <= 1'b0;                           // Sin dato válido
      o_status_ok    <= 1'b1;                           // Estado OK por defecto al arrancar
      o_status_warn  <= 1'b0;                           // Sin advertencia
      o_status_alert <= 1'b0;                           // Sin alerta
    end
    else begin
      if (r_stage1_valid) begin
        // CAPTURA: Registrar todos los resultados de Etapa 2 cuando Etapa 1 completó.
        o_flow_raw     <= r_flow_raw;                   // Propagar caudal bruto al top-level
        o_flow_cal     <= w_flow_cal;                   // Propagar caudal calibrado (para display y UART)
        o_error        <= r_error;                      // Propagar error al fuzzy_controller (feedback)
        o_deriv_out    <= r_deriv;                      // Propagar derivada al fuzzy_controller (feedback)
        o_status_ok    <= w_ok;                         // Actualizar flag de estado normal
        o_status_warn  <= w_warn;                       // Actualizar flag de advertencia
        o_status_alert <= w_alert;                      // Actualizar flag de alerta crítica
      end
      // Propagar strobe de validez con latencia total = 2 ciclos desde i_valid original.
      o_valid <= r_stage1_valid;                        // Dato de salida disponible para consumidores
    end
  end

endmodule : auto_calibrator
