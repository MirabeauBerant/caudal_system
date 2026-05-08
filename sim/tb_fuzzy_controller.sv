//=============================================================================
// tb_fuzzy_controller.sv — Testbench paramétrico del controlador difuso
//
// Escenarios de prueba:
//   1. Error cero, derivada cero        → corrección ≈ 0
//   2. Error negativo grande, dQ/dt neg  → corrección positiva fuerte
//   3. Error positivo grande, dQ/dt pos  → corrección negativa fuerte
//   4. Error pequeño, derivada cero      → corrección leve
//   5. Barrido lineal de error           → respuesta monótona
//   6. Reset durante operación           → recuperación limpia
//=============================================================================

`timescale 1ns / 1ps

import fuzzy_pkg::*;

module tb_fuzzy_controller;

  // ── Señales ──
  logic                            clk;
  logic                            rst_n;
  logic signed [INPUT_WIDTH-1:0]   error_in;
  logic signed [INPUT_WIDTH-1:0]   deriv_in;
  logic                            valid_in;
  logic signed [OUTPUT_WIDTH-1:0]  correction_out;
  logic                            valid_out;

  // ── DUT ──
  fuzzy_controller dut (
    .i_clk        (clk),
    .i_rst_n      (rst_n),
    .i_error      (error_in),
    .i_deriv      (deriv_in),
    .i_valid      (valid_in),
    .o_correction (correction_out),
    .o_valid      (valid_out)
  );

  // ── Reloj: 50 MHz (20 ns periodo) ──
  initial clk = 0;
  always #10 clk = ~clk;

  // ── Tarea auxiliar: aplicar estímulo y esperar resultado ──
  task automatic apply_stimulus(
    input logic signed [INPUT_WIDTH-1:0] err,
    input logic signed [INPUT_WIDTH-1:0] drv,
    input string test_name
  );
    @(posedge clk);
    error_in = err;
    deriv_in = drv;
    valid_in = 1'b1;
    @(posedge clk);
    valid_in = 1'b0;

    // Esperar pipeline (4 ciclos)
    repeat(5) @(posedge clk);

    $display("[%0t] %s: error=%0d, deriv=%0d => correction=%0d (valid=%b)",
             $time, test_name, err, drv, correction_out, valid_out);
  endtask

  // ── Secuencia principal ──
  initial begin
    $display("======================================================");
    $display(" Testbench: Controlador Difuso Takagi-Sugeno");
    $display("======================================================");

    // Reset
    rst_n    = 1'b0;
    error_in = '0;
    deriv_in = '0;
    valid_in = 1'b0;
    repeat(5) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    // ── Test 1: Error=0, Derivada=0 → Corrección ≈ 0 ──
    apply_stimulus(16'sd0, 16'sd0, "T1_ZERO_ZERO");

    // ── Test 2: Error negativo grande → Corrección positiva ──
    apply_stimulus(-16'sd80, -16'sd32, "T2_NB_NEG");

    // ── Test 3: Error positivo grande → Corrección negativa ──
    apply_stimulus(16'sd80, 16'sd32, "T3_PB_POS");

    // ── Test 4: Error pequeño negativo → Corrección leve ──
    apply_stimulus(-16'sd20, 16'sd0, "T4_NS_ZERO");

    // ── Test 5: Error pequeño positivo → Corrección leve neg ──
    apply_stimulus(16'sd20, 16'sd0, "T5_PS_ZERO");

    // ── Test 6: Barrido lineal ──
    $display("--- Barrido lineal de error (-100 a +100) ---");
    for (int e = -100; e <= 100; e = e + 20) begin
      apply_stimulus(16'(e), 16'sd0, "SWEEP");
    end

    // ── Test 7: Reset mid-operation ──
    @(posedge clk);
    error_in = -16'sd60;
    deriv_in = -16'sd16;
    valid_in = 1'b1;
    @(posedge clk);
    valid_in = 1'b0;
    @(posedge clk);
    rst_n = 1'b0;  // Reset en medio del pipeline
    repeat(3) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);
    $display("[%0t] T7_RESET: After reset => correction=%0d, valid=%b",
             $time, correction_out, valid_out);

    // ── Fin ──
    repeat(10) @(posedge clk);
    $display("======================================================");
    $display(" Testbench COMPLETADO");
    $display("======================================================");
    $finish;
  end

  // ── Monitor continuo ──
  always @(posedge clk) begin
    if (valid_out)
      $display("  [MONITOR %0t] correction = %0d", $time, correction_out);
  end

endmodule : tb_fuzzy_controller
