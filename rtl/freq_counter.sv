//=============================================================================
// freq_counter.sv — Contador de Frecuencia con Derivada
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Cuenta los pulsos del detector de flancos durante una ventana
//   temporal de 1 segundo (controlada por i_window_tick del clk_divider).
//   Al final de cada ventana:
//     1. Captura el conteo como frecuencia (Hz ≈ pulsos/seg)
//     2. Calcula la derivada: dFreq = freq_actual - freq_anterior
//     3. Reinicia el contador para la siguiente ventana
//
//   Conversión a caudal (L/min) según ecuación del fabricante:
//     Q(L/min) = (F + 3) / 7.5
//   Esta conversión se realiza downstream o en el top-level.
//
//   Ecuación sensor YF-S201:
//     F = 7.5 * Q − 3  →  450 pulsos/litro
//
// Salidas:
//   o_freq       — Frecuencia medida (pulsos en la ventana), unsigned 16-bit
//   o_freq_prev  — Frecuencia anterior (para derivada externa si se requiere)
//   o_deriv      — Derivada de frecuencia (signed): freq - freq_prev
//   o_valid      — Pulso de 1 ciclo cuando los datos son válidos
//
// Recursos estimados: ~48 FFs, ~30 LUTs
//=============================================================================

module freq_counter #(
  parameter int COUNT_WIDTH = 16
)(
  input  logic                            i_clk,
  input  logic                            i_rst_n,
  input  logic                            i_pulse,        // Del pulse_detector
  input  logic                            i_window_tick,  // Tick de 1 segundo
  output logic [COUNT_WIDTH-1:0]          o_freq,         // Frecuencia actual (Hz)
  output logic signed [COUNT_WIDTH-1:0]   o_deriv,        // dFreq/dt (signed)
  output logic                            o_valid         // Dato nuevo disponible
);

  // ── Contador de pulsos en ventana activa ──
  logic [COUNT_WIDTH-1:0] r_count;

  // ── Registros de resultado ──
  logic [COUNT_WIDTH-1:0] r_freq;
  logic [COUNT_WIDTH-1:0] r_freq_prev;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_count     <= '0;
      r_freq      <= '0;
      r_freq_prev <= '0;
      o_freq      <= '0;
      o_deriv     <= '0;
      o_valid     <= 1'b0;
    end
    else begin
      o_valid <= 1'b0;  // Por defecto no válido

      if (i_window_tick) begin
        // ── Fin de ventana: capturar resultado ──
        r_freq_prev <= r_freq;
        r_freq      <= r_count;
        o_freq      <= r_count;
        // Derivada: diferencia entre mediciones consecutivas
        o_deriv     <= $signed({1'b0, r_count}) - $signed({1'b0, r_freq});
        o_valid     <= 1'b1;
        r_count     <= '0;   // Reiniciar para siguiente ventana
      end
      else if (i_pulse) begin
        // ── Acumular pulso ──
        if (r_count != {COUNT_WIDTH{1'b1}})   // Protección contra overflow
          r_count <= r_count + 1'b1;
      end
    end
  end

endmodule : freq_counter
