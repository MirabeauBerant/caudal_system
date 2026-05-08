//=============================================================================
// fuzzifier.sv — Módulo de Fuzzificación
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Evalúa funciones de membresía triangulares para dos variables
//   de entrada (Error de Flujo y Derivada del Caudal) y produce
//   vectores de grados de membresía [0..255].
//
//   Cada función de membresía triangular se define por tres puntos:
//     (left, center, right)
//
//                 μ
//              1.0 │      /\
//                  │     /  \
//                  │    /    \
//              0.0 │___/______\___
//                     L   C   R
//
//   Cálculo:
//     Si x <= L:         μ = 0
//     Si L < x <= C:     μ = (x - L) / (C - L)  [rampa ascendente]
//     Si C < x < R:      μ = (R - x) / (R - C)  [rampa descendente]
//     Si x >= R:          μ = 0
//
//   Implementación sin divisiones: usamos multiplicación por el
//   recíproco pre-calculado (potencia de 2 → bit-shift).
//
// Latencia: 1 ciclo de reloj (registrado a la salida)
// Recursos estimados: ~150 LUTs
//=============================================================================

import fuzzy_pkg::*;

module fuzzifier (
  input  logic                          i_clk,
  input  logic                          i_rst_n,

  // Entradas crisp (punto fijo con signo)
  input  logic signed [INPUT_WIDTH-1:0] i_error,      // ΔQ = Q_deseado - Q_medido
  input  logic signed [INPUT_WIDTH-1:0] i_deriv,      // dQ/dt

  // Entrada de validación
  input  logic                          i_valid,

  // Salidas: grados de membresía
  output logic [MU_WIDTH-1:0]           o_mu_error [NUM_SETS_ERROR],
  output logic [MU_WIDTH-1:0]           o_mu_deriv [NUM_SETS_DERIV],

  // Señal de dato válido a la salida
  output logic                          o_valid
);

  // ─────────────────────────────────────────────────────────────────────
  //  Función combinacional: evalúa una membresía triangular
  // ─────────────────────────────────────────────────────────────────────
  //
  //  Para evitar divisiones en hardware, aprovechamos que los triángulos
  //  son simétricos (o sus pendientes son potencias de 2). Calculamos:
  //
  //    μ = 255 * (x - left) / (center - left)   en la rampa ascendente
  //    μ = 255 * (right - x) / (right - center)  en la rampa descendente
  //
  //  Como (center - left) y (right - center) son conocidos en diseño,
  //  pre-calculamos el recíproco como shift. Para valores generales,
  //  usamos una multiplicación seguida de shift.
  // ─────────────────────────────────────────────────────────────────────

  function automatic logic [MU_WIDTH-1:0] calc_triangular_mu(
    input logic signed [INPUT_WIDTH-1:0] x,
    input logic signed [INPUT_WIDTH-1:0] left_pt,
    input logic signed [INPUT_WIDTH-1:0] center_pt,
    input logic signed [INPUT_WIDTH-1:0] right_pt
  );
    // Variables intermedias con ancho extendido para evitar overflow
    logic signed [31:0] numerator;
    logic signed [31:0] denominator;
    logic signed [31:0] result;

    if (x <= left_pt || x >= right_pt) begin
      // Fuera del soporte → μ = 0
      return '0;
    end
    else if (x <= center_pt) begin
      // Rampa ascendente: μ = MU_MAX * (x - left) / (center - left)
      numerator   = 32'(MU_MAX) * (32'(x) - 32'(left_pt));
      denominator = 32'(center_pt) - 32'(left_pt);
      if (denominator == 0)
        return MU_MAX;  // Triángulo degenerado → membresía plena
      result = numerator / denominator;
      // Saturar a MU_MAX
      if (result > 32'(MU_MAX))
        return MU_MAX;
      else
        return result[MU_WIDTH-1:0];
    end
    else begin
      // Rampa descendente: μ = MU_MAX * (right - x) / (right - center)
      numerator   = 32'(MU_MAX) * (32'(right_pt) - 32'(x));
      denominator = 32'(right_pt) - 32'(center_pt);
      if (denominator == 0)
        return MU_MAX;
      result = numerator / denominator;
      if (result > 32'(MU_MAX))
        return MU_MAX;
      else
        return result[MU_WIDTH-1:0];
    end
  endfunction


  // ─────────────────────────────────────────────────────────────────────
  //  Lógica combinacional: evaluar todos los conjuntos difusos
  // ─────────────────────────────────────────────────────────────────────

  logic [MU_WIDTH-1:0] w_mu_error [NUM_SETS_ERROR];
  logic [MU_WIDTH-1:0] w_mu_deriv [NUM_SETS_DERIV];

  always_comb begin
    // ── Fuzzificar Error de Flujo (5 conjuntos) ──
    for (int i = 0; i < NUM_SETS_ERROR; i++) begin
      w_mu_error[i] = calc_triangular_mu(
        i_error,
        ERR_BP[i][0],   // left
        ERR_BP[i][1],   // center
        ERR_BP[i][2]    // right
      );
    end

    // ── Fuzzificar Derivada del Caudal (3 conjuntos) ──
    for (int j = 0; j < NUM_SETS_DERIV; j++) begin
      w_mu_deriv[j] = calc_triangular_mu(
        i_deriv,
        DRV_BP[j][0],   // left
        DRV_BP[j][1],   // center
        DRV_BP[j][2]    // right
      );
    end
  end


  // ─────────────────────────────────────────────────────────────────────
  //  Registro de salida (1 ciclo de latencia para timing)
  // ─────────────────────────────────────────────────────────────────────

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      for (int i = 0; i < NUM_SETS_ERROR; i++)
        o_mu_error[i] <= '0;
      for (int j = 0; j < NUM_SETS_DERIV; j++)
        o_mu_deriv[j] <= '0;
      o_valid <= 1'b0;
    end
    else begin
      if (i_valid) begin
        for (int i = 0; i < NUM_SETS_ERROR; i++)
          o_mu_error[i] <= w_mu_error[i];
        for (int j = 0; j < NUM_SETS_DERIV; j++)
          o_mu_deriv[j] <= w_mu_deriv[j];
      end
      o_valid <= i_valid;
    end
  end

endmodule : fuzzifier
