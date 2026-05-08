//=============================================================================
// caudal_system_top.sv — Top-Level del Sistema Caudalímetro Difuso
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Módulo top-level que integra todo el pipeline del caudalímetro:
//
//   ┌─────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────────┐
//   │   Pulse     │──>│   Freq     │──>│    EMA     │──>│     Auto       │
//   │  Detector   │   │  Counter   │   │   Filter   │   │  Calibrator    │
//   └─────────────┘   └────────────┘   └────────────┘   └───────┬────────┘
//                                                          ↑    │    ↓
//                                                     ┌────┘    │  ┌────────────┐
//                                                     │         │  │  7-Seg     │
//                                                ┌────┴───┐     │  │  Display   │
//                                                │  Fuzzy │     │  └────────────┘
//                                                │ Control│     │  ┌────────────┐
//                                                └────────┘     └─>│    LED     │
//                                                                  │   Status   │
//                                                                  └────────────┘
//
//   Pipeline total:
//     Sensor → Pulse Detect → Freq Count (1s) → EMA → Auto_Cal ←→ Fuzzy
//                                                       ↓
//                                                    Display + LEDs
//
// Interfaces externas:
//   - i_clk_50mhz    : Oscilador de 50 MHz de la placa
//   - i_rst_n        : Reset activo bajo (botón)
//   - i_sensor       : Entrada del sensor YF-S201 (post-conversor nivel)
//   - i_sw           : 4 slide switches para configuración de setpoint
//   - o_seg          : Segmentos del display 7-seg (A..G, DP)
//   - o_dig          : Habilitación de dígitos del display (4)
//
// Board: FPGA Init (4 SW, 4-digit 7-seg, no discrete LEDs)
// Recursos estimados totales: ~500 LUTs, ~300 FFs (≤10% MAX 10 08K)
//=============================================================================

import fuzzy_pkg::*;

module caudal_system_top #(
  parameter int CLK_FREQ        = 50_000_000,
  parameter int DEBOUNCE_TICKS  = 5000,
  parameter int EMA_SHIFT       = 3
)(
  // ── Interfaz externa ──
  input  logic        i_clk_50mhz,
  input  logic        i_rst_n,

  // Sensor
  input  logic        i_sensor,         // YF-S201 (post level-shifter)

  // Configuración (4 slide switches de la placa FPGA Init)
  input  logic [3:0]  i_sw,            // 4 slide switches (SW1-SW4)

  // Display 7 segmentos
  output logic [7:0]  o_seg,           // {dp, g, f, e, d, c, b, a}
  output logic [3:0]  o_dig            // Digit enable (active low)
);

  // ═══════════════════════════════════════════════════════════════════════
  //  SEÑALES INTERNAS
  // ═══════════════════════════════════════════════════════════════════════

  // Clock divider
  logic w_tick_1hz;

  // Pulse detector
  logic w_pulse;

  // Frequency counter
  logic [15:0]          w_freq;
  logic signed [15:0]   w_deriv_raw;
  logic                 w_freq_valid;

  // EMA filters
  logic [15:0]          w_freq_filtered;
  logic                 w_freq_filt_valid;
  logic [15:0]          w_deriv_filtered;
  logic                 w_deriv_filt_valid;

  // Auto calibrator → Fuzzy controller feedback
  logic signed [INPUT_WIDTH-1:0]  w_error;
  logic signed [INPUT_WIDTH-1:0]  w_deriv_fb;
  logic                           w_cal_valid;

  // Fuzzy controller
  logic signed [OUTPUT_WIDTH-1:0] w_correction;
  logic                           w_fuzzy_valid;

  // Auto calibrator outputs
  logic [15:0]  w_flow_raw;
  logic [15:0]  w_flow_cal;
  logic         w_status_ok;
  logic         w_status_warn;
  logic         w_status_alert;

  // Setpoint del caudal (configurado via 4 switches)
  // 4 bits → 16 niveles × 256 (≈ 0 a 15 L/min en Q8.8)
  // SW=0000 → 0 L/min, SW=0001 → 1 L/min, ..., SW=1111 → 15 L/min
  logic [15:0] w_setpoint;
  assign w_setpoint = {4'b0, i_sw, 8'b0};  // i_sw × 256 → Q8.8 entero


  // ═══════════════════════════════════════════════════════════════════════
  //  INSTANCIACIÓN DE MÓDULOS
  // ═══════════════════════════════════════════════════════════════════════

  // ── 1. Clock Divider: genera tick de 1 Hz ──
  clk_divider #(
    .CLK_FREQ  (CLK_FREQ),
    .TARGET_HZ (1)
  ) u_clk_div_1hz (
    .i_clk   (i_clk_50mhz),
    .i_rst_n (i_rst_n),
    .o_tick  (w_tick_1hz)
  );

  // ── 2. Pulse Detector: sincroniza y detecta flancos del sensor ──
  pulse_detector #(
    .DEBOUNCE_TICKS (DEBOUNCE_TICKS)
  ) u_pulse_det (
    .i_clk        (i_clk_50mhz),
    .i_rst_n      (i_rst_n),
    .i_sensor_raw (i_sensor),
    .o_pulse      (w_pulse)
  );

  // ── 3. Frequency Counter: cuenta pulsos en ventana de 1 segundo ──
  freq_counter #(
    .COUNT_WIDTH (16)
  ) u_freq_cnt (
    .i_clk         (i_clk_50mhz),
    .i_rst_n       (i_rst_n),
    .i_pulse       (w_pulse),
    .i_window_tick (w_tick_1hz),
    .o_freq        (w_freq),
    .o_deriv       (w_deriv_raw),
    .o_valid       (w_freq_valid)
  );

  // ── 4a. EMA Filter: suavizado de frecuencia ──
  ema_filter #(
    .DATA_WIDTH  (16),
    .SHIFT_BITS  (EMA_SHIFT),
    .SIGNED_DATA (0)           // Frecuencia es unsigned
  ) u_ema_freq (
    .i_clk      (i_clk_50mhz),
    .i_rst_n    (i_rst_n),
    .i_data     (w_freq),
    .i_valid    (w_freq_valid),
    .o_filtered (w_freq_filtered),
    .o_valid    (w_freq_filt_valid)
  );

  // ── 4b. EMA Filter: suavizado de derivada ──
  ema_filter #(
    .DATA_WIDTH  (16),
    .SHIFT_BITS  (EMA_SHIFT),
    .SIGNED_DATA (1)           // Derivada es signed
  ) u_ema_deriv (
    .i_clk      (i_clk_50mhz),
    .i_rst_n    (i_rst_n),
    .i_data     (w_deriv_raw),
    .i_valid    (w_freq_valid),
    .o_filtered (w_deriv_filtered),
    .o_valid    (w_deriv_filt_valid)
  );

  // ── 5. Auto Calibrator: conversión a caudal + corrección ──
  auto_calibrator #(
    .BUBBLE_THRESHOLD (50),
    .FLOW_SCALE       (34)
  ) u_auto_cal (
    .i_clk          (i_clk_50mhz),
    .i_rst_n        (i_rst_n),
    .i_freq         (w_freq_filtered),
    .i_deriv        ($signed(w_deriv_filtered)),
    .i_valid        (w_freq_filt_valid),
    .i_correction   (w_correction),
    .i_setpoint     (w_setpoint),
    .o_flow_raw     (w_flow_raw),
    .o_flow_cal     (w_flow_cal),
    .o_error        (w_error),
    .o_deriv_out    (w_deriv_fb),
    .o_valid        (w_cal_valid),
    .o_status_ok    (w_status_ok),
    .o_status_warn  (w_status_warn),
    .o_status_alert (w_status_alert)
  );

  // ── 6. Fuzzy Controller: motor difuso Takagi-Sugeno ──
  fuzzy_controller u_fuzzy_ctrl (
    .i_clk        (i_clk_50mhz),
    .i_rst_n      (i_rst_n),
    .i_error      (w_error),
    .i_deriv      (w_deriv_fb),
    .i_valid      (w_cal_valid),
    .o_correction (w_correction),
    .o_valid      (w_fuzzy_valid)
  );

  // ── 7. Seven Segment Display: muestra caudal calibrado ──
  seven_seg_driver #(
    .CLK_FREQ   (CLK_FREQ),
    .REFRESH_HZ (1000),
    .NUM_DIGITS (4)
  ) u_7seg (
    .i_clk      (i_clk_50mhz),
    .i_rst_n    (i_rst_n),
    .i_value    (w_flow_cal),      // Caudal calibrado Q8.8
    .o_segments (o_seg),
    .o_digit_en (o_dig)
  );

  // ── 8. LED Status: indicadores de diagnóstico ──
  // Nota: La placa FPGA Init no tiene LEDs discretos.
  // Las señales se mantienen internas para depuración futura
  // (conectar a pines GPIO de expansión si se desea).
  logic [3:0] w_led_internal;

  led_status #(
    .CLK_FREQ (CLK_FREQ)
  ) u_led_status (
    .i_clk           (i_clk_50mhz),
    .i_rst_n         (i_rst_n),
    .i_status_ok     (w_status_ok),
    .i_status_warn   (w_status_warn),
    .i_status_alert  (w_status_alert),
    .i_tick_1hz      (w_tick_1hz),
    .o_led_ok        (w_led_internal[0]),
    .o_led_warn      (w_led_internal[1]),
    .o_led_alert     (w_led_internal[2]),
    .o_led_heartbeat (w_led_internal[3])
  );

endmodule : caudal_system_top
