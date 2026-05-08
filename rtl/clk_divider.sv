//=============================================================================
// clk_divider.sv — Divisor de Reloj Parametrizable
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Genera un pulso de 1 ciclo de reloj a frecuencia reducida.
//   Configurado por defecto para producir un tick de 1 Hz (ventana
//   de 1 segundo) a partir del reloj base de 50 MHz.
//
//   Usos principales:
//     - Ventana de conteo para freq_counter (1 segundo)
//     - Refresh de display 7 segmentos (~1 kHz)
//     - Parpadeo de LEDs de diagnóstico
//
// Parámetros:
//   CLK_FREQ   — Frecuencia del reloj de entrada en Hz
//   TARGET_HZ  — Frecuencia deseada del tick de salida en Hz
//
// Recursos estimados: ~26 FFs (contador 26-bit), ~30 LUTs
//=============================================================================

module clk_divider #(
  parameter int CLK_FREQ  = 50_000_000,   // 50 MHz
  parameter int TARGET_HZ = 1             // 1 Hz por defecto
)(
  input  logic i_clk,
  input  logic i_rst_n,
  output logic o_tick      // Pulso de 1 ciclo a TARGET_HZ
);

  // Número de ciclos por periodo de salida
  localparam int COUNT_MAX = CLK_FREQ / TARGET_HZ - 1;

  // Ancho del contador (bits necesarios)
  localparam int CNT_WIDTH = $clog2(COUNT_MAX + 1);

  logic [CNT_WIDTH-1:0] r_count;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_count <= '0;
      o_tick  <= 1'b0;
    end
    else begin
      if (r_count == CNT_WIDTH'(COUNT_MAX)) begin
        r_count <= '0;
        o_tick  <= 1'b1;
      end
      else begin
        r_count <= r_count + 1'b1;
        o_tick  <= 1'b0;
      end
    end
  end

endmodule : clk_divider
