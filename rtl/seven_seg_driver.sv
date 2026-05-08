//=============================================================================
// seven_seg_driver.sv — Driver de Display 7 Segmentos Multiplexado
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Controla 4 dígitos de display 7 segmentos en modo multiplexado.
//   Recibe un valor BCD de 16 bits (4 dígitos × 4 bits) y multiplexa
//   la salida a ~1 kHz para persistencia visual.
//
//   Muestra el caudal en formato XX.XX L/min:
//     - Dígito 3 (MSB): decenas de L/min
//     - Dígito 2:       unidades de L/min
//     - Dígito 1:       décimas
//     - Dígito 0 (LSB): centésimas
//     - Punto decimal entre dígito 2 y 1
//
// Convención de segmentos (ánodo común, activo bajo):
//     ─── a ───
//    |         |
//    f         b
//    |         |
//     ─── g ───
//    |         |
//    e         c
//    |         |
//     ─── d ───  (dp)
//
//   Segmentos: {dp, g, f, e, d, c, b, a} — activo BAJO
//
// Entradas:
//   i_value  — Valor Q8.8 del caudal (se convierte internamente a BCD)
//
// Recursos estimados: ~40 FFs, ~60 LUTs
//=============================================================================

module seven_seg_driver #(
  parameter int CLK_FREQ      = 50_000_000,
  parameter int REFRESH_HZ    = 1000,        // Frecuencia de multiplexación
  parameter int NUM_DIGITS    = 4
)(
  input  logic        i_clk,
  input  logic        i_rst_n,
  input  logic [15:0] i_value,    // Caudal en Q8.8 (L/min × 256)

  // Salidas hacia el hardware del display
  output logic [7:0]  o_segments, // {dp, g, f, e, d, c, b, a} activo bajo
  output logic [3:0]  o_digit_en  // Habilitación de dígito (activo bajo)
);

  // ── Conversión Q8.8 a decimal (XX.XX) ──
  // Parte entera: i_value[15:8]  (0-255, pero práctico 0-30 L/min)
  // Parte fraccionaria: i_value[7:0] * 100 / 256
  //   Aproximación: frac_decimal ≈ i_value[7:0] * 100 >> 8

  logic [7:0]  w_integer_part;
  logic [15:0] w_frac_product;
  logic [6:0]  w_frac_decimal;   // 0-99

  assign w_integer_part = i_value[15:8];
  assign w_frac_product = {8'b0, i_value[7:0]} * 16'd100;
  assign w_frac_decimal = w_frac_product[15:8];  // >> 8

  // ── Extracción de dígitos BCD ──
  logic [3:0] w_digits [NUM_DIGITS];

  always_comb begin
    // Dígito 3: decenas de L/min
    w_digits[3] = 4'(w_integer_part / 10);
    // Dígito 2: unidades de L/min
    w_digits[2] = 4'(w_integer_part % 10);
    // Dígito 1: décimas
    w_digits[1] = 4'(w_frac_decimal / 10);
    // Dígito 0: centésimas
    w_digits[0] = 4'(w_frac_decimal % 10);
  end

  // ── Tabla de decodificación BCD → 7 segmentos ──
  // Segmentos: {dp, g, f, e, d, c, b, a} — activo BAJO (0 = encendido)
  function automatic logic [7:0] bcd_to_seg(input logic [3:0] bcd, input logic dp);
    logic [6:0] seg;
    case (bcd)
      4'd0: seg = 7'b100_0000;  // 0
      4'd1: seg = 7'b111_1001;  // 1
      4'd2: seg = 7'b010_0100;  // 2
      4'd3: seg = 7'b011_0000;  // 3
      4'd4: seg = 7'b001_1001;  // 4
      4'd5: seg = 7'b001_0010;  // 5
      4'd6: seg = 7'b000_0010;  // 6
      4'd7: seg = 7'b111_1000;  // 7
      4'd8: seg = 7'b000_0000;  // 8
      4'd9: seg = 7'b001_0000;  // 9
      default: seg = 7'b111_1111;  // Apagado
    endcase
    return {~dp, seg};  // dp activo bajo
  endfunction

  // ── Multiplexación de dígitos ──
  localparam int MUX_COUNT_MAX = CLK_FREQ / (REFRESH_HZ * NUM_DIGITS) - 1;
  localparam int MUX_WIDTH     = $clog2(MUX_COUNT_MAX + 1);

  logic [MUX_WIDTH-1:0] r_mux_count;
  logic [1:0]           r_active_digit;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_mux_count    <= '0;
      r_active_digit <= 2'd0;
    end
    else begin
      if (r_mux_count == MUX_WIDTH'(MUX_COUNT_MAX)) begin
        r_mux_count    <= '0;
        r_active_digit <= r_active_digit + 2'd1;
      end
      else begin
        r_mux_count <= r_mux_count + 1'b1;
      end
    end
  end

  // ── Salida de segmentos y habilitación ──
  always_comb begin
    // Punto decimal solo en dígito 2 (entre enteros y fracción)
    o_segments = bcd_to_seg(w_digits[r_active_digit],
                            (r_active_digit == 2'd2));

    // Habilitación de dígito (activo bajo)
    o_digit_en = 4'b1111;
    o_digit_en[r_active_digit] = 1'b0;
  end

endmodule : seven_seg_driver
