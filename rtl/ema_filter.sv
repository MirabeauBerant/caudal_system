//=============================================================================
// ema_filter.sv — Filtro de Media Móvil Exponencial (EMA)
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Implementa un filtro EMA (Exponential Moving Average) para suavizar
//   las mediciones de frecuencia y derivada antes del motor difuso.
//
//   Ecuación:
//     y[n] = α · x[n] + (1 − α) · y[n-1]
//
//   Implementación sin multiplicaciones:
//     α = 1/(2^SHIFT_BITS), implementado como desplazamiento a la derecha.
//
//     y[n] = y[n-1] + (x[n] - y[n-1]) >> SHIFT_BITS
//
//   Con SHIFT_BITS=3:  α = 1/8 = 0.125 (suavizado moderado)
//   Con SHIFT_BITS=4:  α = 1/16 = 0.0625 (suavizado fuerte)
//
// Parámetros:
//   DATA_WIDTH  — Ancho de datos (default: 16 bits)
//   SHIFT_BITS  — Bits de shift para α (default: 3 → α=1/8)
//   SIGNED_DATA — Si los datos son con signo (default: 1 = signed)
//
// Latencia: 1 ciclo de reloj
// Recursos estimados: ~20 FFs, ~25 LUTs
//=============================================================================

module ema_filter #(
  parameter int DATA_WIDTH  = 16,
  parameter int SHIFT_BITS  = 3,
  parameter int SIGNED_DATA = 1     // 1 = datos signed, 0 = unsigned
)(
  input  logic                          i_clk,
  input  logic                          i_rst_n,
  input  logic [DATA_WIDTH-1:0]         i_data,      // Dato de entrada
  input  logic                          i_valid,     // Strobe de dato nuevo
  output logic [DATA_WIDTH-1:0]         o_filtered,  // Dato filtrado
  output logic                          o_valid      // Strobe de salida
);

  // Ancho extendido para cálculo intermedio (evitar pérdida de precisión)
  localparam int EXT_WIDTH = DATA_WIDTH + SHIFT_BITS;

  // Acumulador interno con precisión extendida
  logic signed [EXT_WIDTH-1:0] r_accum;

  // Señales intermedias
  logic signed [EXT_WIDTH-1:0] w_input_ext;
  logic signed [EXT_WIDTH-1:0] w_diff;
  logic signed [EXT_WIDTH-1:0] w_delta;
  logic signed [EXT_WIDTH-1:0] w_new_accum;

  generate
    if (SIGNED_DATA) begin : gen_signed
      assign w_input_ext = EXT_WIDTH'($signed(i_data)) <<< SHIFT_BITS;
    end
    else begin : gen_unsigned
      assign w_input_ext = EXT_WIDTH'({1'b0, i_data}) <<< SHIFT_BITS;
    end
  endgenerate

  // Diferencia entre entrada (escalada) y acumulador
  assign w_diff  = w_input_ext - r_accum;

  // Delta = diferencia / 2^SHIFT_BITS (el factor α)
  assign w_delta = w_diff >>> SHIFT_BITS;

  // Nuevo valor del acumulador
  assign w_new_accum = r_accum + w_delta;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_accum  <= '0;
      o_valid  <= 1'b0;
    end
    else begin
      o_valid <= 1'b0;
      if (i_valid) begin
        r_accum <= w_new_accum;
        o_valid <= 1'b1;
      end
    end
  end

  // Salida: parte alta del acumulador (descartamos bits de precisión extra)
  generate
    if (SIGNED_DATA) begin : gen_out_signed
      assign o_filtered = DATA_WIDTH'(r_accum >>> SHIFT_BITS);
    end
    else begin : gen_out_unsigned
      assign o_filtered = DATA_WIDTH'(r_accum >> SHIFT_BITS);
    end
  endgenerate

endmodule : ema_filter
