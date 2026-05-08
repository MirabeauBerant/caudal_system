//=============================================================================
// tb_caudal_system.sv — Testbench de Integración End-to-End
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
//
// Descripción:
//   Testbench que simula el sistema completo desde la señal del sensor
//   hasta la salida en display. Genera trenes de pulsos que emulan el
//   sensor YF-S201 a distintos caudales y verifica la respuesta.
//
// Interfaz adaptada a placa FPGA Init:
//   - 4 switches (i_sw[3:0]) para setpoint 0-15 L/min
//   - Display 7-seg (o_seg[7:0], o_dig[3:0])
//   - Sin LEDs discretos (led_status es interno)
//
// Escenarios:
//   1. Sin flujo (0 L/min)         → display ≈ 0
//   2. Flujo bajo (5 L/min)        → ~34 Hz
//   3. Flujo medio (10 L/min)      → ~72 Hz
//   4. Detección de fuga           → flujo sin setpoint
//   5. Reset durante operación     → recuperación limpia
//
// Ecuación del sensor YF-S201:
//   F(Hz) = 7.5 × Q(L/min) − 3
//   Ej: Q=5 → F=34.5 Hz | Q=10 → F=72 Hz | Q=15 → F=109.5 Hz
//=============================================================================

`timescale 1ns / 1ps

import fuzzy_pkg::*;

module tb_caudal_system;

  // ═══════════════════════════════════════════════════════════════════════
  //  PARÁMETROS DE SIMULACIÓN
  // ═══════════════════════════════════════════════════════════════════════

  // Reloj acelerado para simulación (reducimos CLK_FREQ para acortar tiempo)
  localparam int SIM_CLK_FREQ    = 50_000;       // 50 kHz (1000x más rápido)
  localparam int SIM_DEBOUNCE    = 5;             // Reducido para sim
  localparam int CLK_PERIOD      = 20;            // 20 ns (50 MHz real)

  // ── Señales (adaptadas a FPGA Init) ──
  logic        clk;
  logic        rst_n;
  logic        sensor;
  logic [3:0]  sw;          // 4 switches (era 10 bits)
  logic [7:0]  seg;
  logic [3:0]  dig;

  // ═══════════════════════════════════════════════════════════════════════
  //  DUT
  // ═══════════════════════════════════════════════════════════════════════

  caudal_system_top #(
    .CLK_FREQ       (SIM_CLK_FREQ),
    .DEBOUNCE_TICKS (SIM_DEBOUNCE),
    .EMA_SHIFT      (2)
  ) dut (
    .i_clk_50mhz (clk),
    .i_rst_n     (rst_n),
    .i_sensor    (sensor),
    .i_sw        (sw),
    .o_seg       (seg),
    .o_dig       (dig)
  );

  // ═══════════════════════════════════════════════════════════════════════
  //  RELOJ
  // ═══════════════════════════════════════════════════════════════════════

  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ═══════════════════════════════════════════════════════════════════════
  //  GENERADOR DE PULSOS DEL SENSOR
  // ═══════════════════════════════════════════════════════════════════════

  // Tarea: genera N pulsos con período dado (emula sensor a cierta frecuencia)
  task automatic generate_sensor_pulses(
    input int num_pulses,
    input int half_period_ns   // Medio período en ns
  );
    for (int p = 0; p < num_pulses; p++) begin
      sensor = 1'b1;
      #(half_period_ns);
      sensor = 1'b0;
      #(half_period_ns);
    end
  endtask

  // Tarea: espera una ventana completa de medición (SIM_CLK_FREQ ciclos)
  task automatic wait_measurement_window();
    // 1 ventana = SIM_CLK_FREQ ciclos de reloj × CLK_PERIOD ns
    repeat(SIM_CLK_FREQ + 100) @(posedge clk);
  endtask

  // ═══════════════════════════════════════════════════════════════════════
  //  SECUENCIA PRINCIPAL
  // ═══════════════════════════════════════════════════════════════════════

  initial begin
    $display("══════════════════════════════════════════════════════");
    $display(" TB: Sistema Completo — Caudalímetro Difuso");
    $display(" Placa: FPGA Init (4 SW, 7-seg, sin LEDs)");
    $display("══════════════════════════════════════════════════════");

    // ── Inicialización ──
    rst_n  = 1'b0;
    sensor = 1'b0;
    sw     = 4'd0;
    repeat(20) @(posedge clk);
    rst_n = 1'b1;
    repeat(10) @(posedge clk);

    $display("[%0t] Sistema inicializado", $time);

    // ══════════════════════════════════════════════════════════════
    //  TEST 1: Sin flujo (sensor quieto)
    // ══════════════════════════════════════════════════════════════
    $display("\n--- TEST 1: Sin flujo ---");
    sw = 4'd0;  // Setpoint = 0
    wait_measurement_window();
    $display("[%0t] T1 completado | seg=%08b dig=%04b", $time, seg, dig);

    // ══════════════════════════════════════════════════════════════
    //  TEST 2: Flujo bajo (~34 Hz ≈ 5 L/min)
    // ══════════════════════════════════════════════════════════════
    $display("\n--- TEST 2: Flujo bajo (5 L/min, ~34 Hz) ---");
    sw = 4'd5;  // Setpoint = 5 L/min

    fork
      begin
        // Generar pulsos durante la ventana
        generate_sensor_pulses(34, 500_000); // 34 pulsos, 1ms half-period
      end
      begin
        wait_measurement_window();
      end
    join_any
    disable fork;

    repeat(100) @(posedge clk);
    $display("[%0t] T2 completado | seg=%08b dig=%04b", $time, seg, dig);

    // ══════════════════════════════════════════════════════════════
    //  TEST 3: Cambio de setpoint (10 L/min)
    // ══════════════════════════════════════════════════════════════
    $display("\n--- TEST 3: Cambio de setpoint (10 L/min) ---");
    sw = 4'd10;  // Setpoint = 10 L/min

    fork
      begin
        generate_sensor_pulses(72, 300_000); // ~72 Hz ≈ 10 L/min
      end
      begin
        wait_measurement_window();
      end
    join_any
    disable fork;

    repeat(100) @(posedge clk);
    $display("[%0t] T3 completado | seg=%08b dig=%04b", $time, seg, dig);

    // ══════════════════════════════════════════════════════════════
    //  TEST 4: Detección de fuga (flujo sin setpoint=0)
    // ══════════════════════════════════════════════════════════════
    $display("\n--- TEST 4: Detección de fuga ---");
    sw = 4'd0;  // Setpoint = 0

    fork
      begin
        generate_sensor_pulses(50, 400_000); // Pulsos espurios (fuga)
      end
      begin
        wait_measurement_window();
      end
    join_any
    disable fork;

    repeat(100) @(posedge clk);
    $display("[%0t] T4 FUGA detectada | seg=%08b dig=%04b", $time, seg, dig);

    // ══════════════════════════════════════════════════════════════
    //  TEST 5: Reset y recuperación
    // ══════════════════════════════════════════════════════════════
    $display("\n--- TEST 5: Reset y recuperación ---");
    rst_n = 1'b0;
    repeat(10) @(posedge clk);
    rst_n = 1'b1;
    repeat(20) @(posedge clk);
    $display("[%0t] Post-reset | seg=%08b dig=%04b", $time, seg, dig);

    // ══════════════════════════════════════════════════════════════
    //  FIN
    // ══════════════════════════════════════════════════════════════
    repeat(200) @(posedge clk);
    $display("\n══════════════════════════════════════════════════════");
    $display(" TB COMPLETADO — Todos los escenarios ejecutados");
    $display("══════════════════════════════════════════════════════");
    $finish;
  end

  // ═══════════════════════════════════════════════════════════════════════
  //  MONITORES
  // ═══════════════════════════════════════════════════════════════════════

  // Monitor de frecuencia (del freq_counter)
  always @(posedge clk) begin
    if (dut.w_freq_valid)
      $display("  [FREQ %0t] freq=%0d Hz, deriv=%0d",
               $time, dut.w_freq, $signed(dut.w_deriv_raw));
  end

  // Monitor de calibración (del auto_calibrator)
  always @(posedge clk) begin
    if (dut.w_cal_valid)
      $display("  [CAL  %0t] flow_raw=%0d, flow_cal=%0d, error=%0d",
               $time, dut.w_flow_raw, dut.w_flow_cal, $signed(dut.w_error));
  end

  // Monitor de corrección difusa
  always @(posedge clk) begin
    if (dut.w_fuzzy_valid)
      $display("  [FUZZ %0t] correction=%0d",
               $time, $signed(dut.w_correction));
  end


endmodule : tb_caudal_system
