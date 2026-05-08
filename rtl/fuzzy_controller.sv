//=============================================================================
// fuzzy_controller.sv — Controlador Difuso Takagi-Sugeno (Wrapper)
// Target: Intel MAX 10 · 50 MHz | Latencia total: 4 ciclos
//
// Pipeline:
//   Ciclo 1: Fuzzificación (fuzzifier)
//   Ciclo 2: Evaluación de reglas (rule_base)
//   Ciclo 3: Acumulación (defuzzifier etapa 1)
//   Ciclo 4: División/shift (defuzzifier etapa 2)
//
// Entradas:  Error de flujo (ΔQ) y derivada (dQ/dt) en punto fijo signed
// Salida:    Señal de corrección signed para autocalibración
//=============================================================================
import fuzzy_pkg::*;

module fuzzy_controller (
  input  logic                            i_clk,
  input  logic                            i_rst_n,
  input  logic signed [INPUT_WIDTH-1:0]   i_error,
  input  logic signed [INPUT_WIDTH-1:0]   i_deriv,
  input  logic                            i_valid,
  output logic signed [OUTPUT_WIDTH-1:0]  o_correction,
  output logic                            o_valid
);

  // ── Señales internas de interconexión ──

  // Fuzzificador → Base de reglas
  logic [MU_WIDTH-1:0] mu_error [NUM_SETS_ERROR];
  logic [MU_WIDTH-1:0] mu_deriv [NUM_SETS_DERIV];
  logic                fuzz_valid;

  // Base de reglas → Defuzzificador
  logic [MU_WIDTH-1:0]             firing_strength [NUM_RULES];
  logic signed [OUTPUT_WIDTH-1:0]  consequent      [NUM_RULES];
  logic                            rules_valid;

  // ── Instanciación del pipeline ──

  fuzzifier u_fuzzifier (
    .i_clk      (i_clk),
    .i_rst_n    (i_rst_n),
    .i_error    (i_error),
    .i_deriv    (i_deriv),
    .i_valid    (i_valid),
    .o_mu_error (mu_error),
    .o_mu_deriv (mu_deriv),
    .o_valid    (fuzz_valid)
  );

  rule_base u_rule_base (
    .i_clk             (i_clk),
    .i_rst_n           (i_rst_n),
    .i_mu_error        (mu_error),
    .i_mu_deriv        (mu_deriv),
    .i_valid           (fuzz_valid),
    .o_firing_strength (firing_strength),
    .o_consequent      (consequent),
    .o_valid           (rules_valid)
  );

  defuzzifier u_defuzzifier (
    .i_clk             (i_clk),
    .i_rst_n           (i_rst_n),
    .i_firing_strength (firing_strength),
    .i_consequent      (consequent),
    .i_valid           (rules_valid),
    .o_correction      (o_correction),
    .o_valid           (o_valid)
  );

endmodule : fuzzy_controller
