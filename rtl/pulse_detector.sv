//=============================================================================
// pulse_detector.sv — Detector de Flancos con Anti-Rebote Digital
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Sincroniza la señal asíncrona del sensor YF-S201 al dominio de
//   reloj de 50 MHz mediante un doble flip-flop, aplica un filtro
//   anti-rebote digital, y genera un pulso limpio de 1 ciclo por
//   cada flanco ascendente detectado.
//
//   Cadena de procesamiento:
//     Sensor → [FF sync 1] → [FF sync 2] → [Debounce] → [Edge detect]
//
// Parámetros:
//   DEBOUNCE_TICKS — Ciclos de estabilidad requeridos antes de aceptar
//                    un cambio. Default: 5000 (~100 μs a 50 MHz).
//                    El YF-S201 genera máx ~225 Hz, así que 100 μs
//                    es seguro contra rebotes mecánicos.
//
// Recursos estimados: ~15 FFs, ~20 LUTs
//=============================================================================

module pulse_detector #(
  parameter int DEBOUNCE_TICKS = 5000   // ~100 μs @ 50 MHz
)(
  input  logic i_clk,
  input  logic i_rst_n,
  input  logic i_sensor_raw,    // Señal directa del sensor (post-conversor de nivel)
  output logic o_pulse          // Pulso limpio: 1 ciclo por flanco ascendente
);

  // ── Sincronizador de doble flip-flop (anti-metaestabilidad) ──
  logic r_sync_1, r_sync_2;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_sync_1 <= 1'b0;
      r_sync_2 <= 1'b0;
    end
    else begin
      r_sync_1 <= i_sensor_raw;
      r_sync_2 <= r_sync_1;
    end
  end

  // ── Filtro anti-rebote digital ──
  localparam int DB_WIDTH = $clog2(DEBOUNCE_TICKS + 1);

  logic [DB_WIDTH-1:0] r_db_count;
  logic                r_debounced;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_db_count  <= '0;
      r_debounced <= 1'b0;
    end
    else begin
      if (r_sync_2 != r_debounced) begin
        // La señal cambió: contar ciclos de estabilidad
        if (r_db_count == DB_WIDTH'(DEBOUNCE_TICKS)) begin
          r_debounced <= r_sync_2;
          r_db_count  <= '0;
        end
        else begin
          r_db_count <= r_db_count + 1'b1;
        end
      end
      else begin
        // La señal es estable: reiniciar contador
        r_db_count <= '0;
      end
    end
  end

  // ── Detector de flanco ascendente ──
  logic r_debounced_prev;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      r_debounced_prev <= 1'b0;
    else
      r_debounced_prev <= r_debounced;
  end

  // Pulso de 1 ciclo en flanco ascendente
  assign o_pulse = r_debounced & ~r_debounced_prev;

endmodule : pulse_detector
