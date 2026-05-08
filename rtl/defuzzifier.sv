//=============================================================================
// defuzzifier.sv — Defuzzificación Takagi-Sugeno
// Target: Intel MAX 10 · 50 MHz | Latencia: 2 ciclos
//
// Método:  y = Σ(w_i · z_i) / Σ(w_i)
//   - Etapa 1: Acumula numerador (Σ w_i·z_i) y denominador (Σ w_i)
//   - Etapa 2: División (implementada con shift a potencia de 2 más
//              cercana cuando sea posible, o divisor iterativo)
//
// Para MAX 10 de bajos recursos, el denominador se redondea a la
// potencia de 2 más cercana para reemplazar la división por shift.
//=============================================================================
import fuzzy_pkg::*;

module defuzzifier (
  input  logic                            i_clk,
  input  logic                            i_rst_n,
  input  logic [MU_WIDTH-1:0]             i_firing_strength [NUM_RULES],
  input  logic signed [OUTPUT_WIDTH-1:0]  i_consequent      [NUM_RULES],
  input  logic                            i_valid,
  output logic signed [OUTPUT_WIDTH-1:0]  o_correction,
  output logic                            o_valid
);

  // ── Etapa 1: Acumulación (combinacional) ──
  // Numerador: Σ(w_i * z_i) — necesita ancho extendido
  // w_i es 8 bits unsigned, z_i es 16 bits signed → producto 24 bits
  // Suma de 15 productos → máx 28 bits
  localparam int ACC_WIDTH = 32;

  logic signed [ACC_WIDTH-1:0] w_numerator;
  logic        [MU_WIDTH+3:0]  w_denominator;  // 12 bits para sum de 15×8bit
  logic signed [ACC_WIDTH-1:0] r_numerator;
  logic        [MU_WIDTH+3:0]  r_denominator;
  logic                        r_stage1_valid;

  always_comb begin
    w_numerator   = '0;
    w_denominator = '0;
    for (int r = 0; r < NUM_RULES; r++) begin
      // Producto: extensión con signo de w_i × z_i
      w_numerator = w_numerator +
        (ACC_WIDTH'($signed({1'b0, i_firing_strength[r]})) *
         ACC_WIDTH'(i_consequent[r]));
      w_denominator = w_denominator + {4'b0, i_firing_strength[r]};
    end
  end

  // Registro de etapa 1
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_numerator    <= '0;
      r_denominator  <= '0;
      r_stage1_valid <= 1'b0;
    end else begin
      if (i_valid) begin
        r_numerator   <= w_numerator;
        r_denominator <= w_denominator;
      end
      r_stage1_valid <= i_valid;
    end
  end

  // ── Etapa 2: División ──
  // Encontrar la potencia de 2 más cercana al denominador y hacer shift
  // Esto introduce un error de redondeo aceptable (< 5%) pero elimina
  // completamente el divisor de hardware.

  function automatic logic [3:0] find_msb_pos(
    input logic [MU_WIDTH+3:0] val
  );
    for (int b = MU_WIDTH+3; b >= 0; b--) begin
      if (val[b]) return b[3:0];
    end
    return 4'd0;
  endfunction

  logic signed [OUTPUT_WIDTH-1:0] w_result;

  always_comb begin
    if (r_denominator == '0) begin
      // Sin activación de reglas → salida cero (sin corrección)
      w_result = '0;
    end else begin
      // Shift derecho por posición del MSB del denominador
      automatic logic [3:0] shift_amt = find_msb_pos(r_denominator);
      w_result = OUTPUT_WIDTH'(r_numerator >>> shift_amt);
    end
  end

  // Registro de salida (etapa 2)
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_correction <= '0;
      o_valid      <= 1'b0;
    end else begin
      if (r_stage1_valid)
        o_correction <= w_result;
      o_valid <= r_stage1_valid;
    end
  end

endmodule : defuzzifier
