//=============================================================================
// led_status.sv — Controlador de LEDs de Estado y Diagnóstico
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Controla 4 LEDs indicadores del estado del sistema:
//
//     LED 0 (Verde)   — OK:     Sistema operando correctamente
//     LED 1 (Amarillo)— WARN:   Advertencia (deriva alta, burbuja)
//     LED 2 (Rojo)    — ALERT:  Alerta crítica (fuga, atasco)
//     LED 3 (Azul)    — DEBUG:  Heartbeat (parpadeo = FPGA activa)
//
//   Modos de parpadeo:
//     - OK:    encendido sólido cuando activo
//     - WARN:  parpadeo lento (1 Hz) cuando activo
//     - ALERT: parpadeo rápido (4 Hz) cuando activo
//     - DEBUG: parpadeo de heartbeat (0.5 Hz)
//
// Recursos estimados: ~10 FFs, ~15 LUTs
//=============================================================================

module led_status #(
  parameter int CLK_FREQ = 50_000_000
)(
  input  logic i_clk,
  input  logic i_rst_n,

  // Señales de estado del auto_calibrator
  input  logic i_status_ok,
  input  logic i_status_warn,
  input  logic i_status_alert,

  // Tick de 1 Hz (del clk_divider principal)
  input  logic i_tick_1hz,

  // Salidas a LEDs (activo alto)
  output logic o_led_ok,        // LED 0: verde
  output logic o_led_warn,      // LED 1: amarillo
  output logic o_led_alert,     // LED 2: rojo
  output logic o_led_heartbeat  // LED 3: heartbeat
);

  // ── Contadores de parpadeo ──
  // Usamos el tick de 1 Hz para generar patrones de parpadeo
  logic [3:0] r_blink_count;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      r_blink_count <= 4'd0;
    else if (i_tick_1hz)
      r_blink_count <= r_blink_count + 4'd1;
  end

  // ── Generación de señales de parpadeo ──
  logic w_blink_slow;   // 0.5 Hz (toggle cada 1 seg)
  logic w_blink_fast;   // 2 Hz (toggle cada 0.25 seg aprox)

  assign w_blink_slow = r_blink_count[0];   // Toggle cada tick
  assign w_blink_fast = r_blink_count[1];   // Toggle cada 2 ticks (pero a 1Hz tick → ~0.5Hz visual)

  // Para parpadeo rápido real, usamos un divisor interno
  localparam int FAST_BLINK_MAX = CLK_FREQ / 8 - 1;  // 4 Hz toggle = 8 semi-períodos/seg
  localparam int FB_WIDTH = $clog2(FAST_BLINK_MAX + 1);

  logic [FB_WIDTH-1:0] r_fast_count;
  logic                r_fast_blink;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_fast_count <= '0;
      r_fast_blink <= 1'b0;
    end
    else begin
      if (r_fast_count == FB_WIDTH'(FAST_BLINK_MAX)) begin
        r_fast_count <= '0;
        r_fast_blink <= ~r_fast_blink;
      end
      else begin
        r_fast_count <= r_fast_count + 1'b1;
      end
    end
  end

  // ── Asignación de LEDs ──
  always_comb begin
    // LED OK: sólido cuando todo bien
    o_led_ok = i_status_ok;

    // LED WARN: parpadeo lento cuando hay advertencia
    o_led_warn = i_status_warn & w_blink_slow;

    // LED ALERT: parpadeo rápido cuando hay alerta
    o_led_alert = i_status_alert & r_fast_blink;

    // LED Heartbeat: siempre parpadea (señal de vida del FPGA)
    o_led_heartbeat = w_blink_slow;
  end

endmodule : led_status
