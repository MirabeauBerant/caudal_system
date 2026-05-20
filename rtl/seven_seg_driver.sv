//=============================================================================
// seven_seg_driver.sv — Driver de Display 7 Segmentos Multiplexado
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Controla 4 dígitos de display 7 segmentos en modo multiplexado.
//   Recibe un valor Q8.8 de 16 bits y muestra el caudal en formato XX.XX L/min.
//
//   Segmentos (ánodo común, activo bajo):
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
// Recursos estimados: ~40 FFs, ~60 LUTs
//=============================================================================

module seven_seg_driver #(
  parameter int CLK_FREQ   = 50_000_000,   // Frecuencia del reloj del sistema (Hz)
  parameter int REFRESH_HZ = 1000,         // Frecuencia de multiplexación (Hz, ~1 kHz sin parpadeo)
  parameter int NUM_DIGITS = 4             // Número de dígitos del display
)(
  input  logic        i_clk,               // Reloj del sistema (50 MHz)
  input  logic        i_rst_n,             // Reset asíncrono activo bajo
  input  logic [15:0] i_value,             // Caudal calibrado en Q8.8 (L/min × 256)

  // ── Salidas hacia el hardware del display ──
  output logic [7:0]  o_segments,          // {dp, g, f, e, d, c, b, a} activo bajo (0 = encendido)
  output logic [3:0]  o_digit_en           // Habilitación de dígito activo bajo (0 = seleccionado)
);

  // ═══════════════════════════════════════════════════════════════════════
  //  Conversión Q8.8 a formato decimal (XX.XX L/min)
  // ═══════════════════════════════════════════════════════════════════════
  // Parte entera: bits [15:8] del Q8.8 (rango 0-255, práctico 0-30 L/min)
  // Parte fraccionaria: bits [7:0] × 100 / 256 → centésimas de L/min

  logic [7:0]  w_integer_part;             // Parte entera del caudal (0-255)
  logic [15:0] w_frac_product;             // Producto intermedio: frac × 100
  logic [6:0]  w_frac_decimal;             // Parte fraccionaria decimal (0-99 centésimas)

  assign w_integer_part = i_value[15:8];   // Extraer byte alto = parte entera del Q8.8
  assign w_frac_product = {8'b0, i_value[7:0]} * 16'd100; // Escalar fracción: frac × 100
  assign w_frac_decimal = w_frac_product[15:8]; // Dividir entre 256 (>> 8) → centésimas

  // ═══════════════════════════════════════════════════════════════════════
  //  Extracción de dígitos BCD individuales
  // ═══════════════════════════════════════════════════════════════════════
  logic [3:0] w_digits [NUM_DIGITS];       // Array de 4 dígitos BCD (0-9 cada uno)

  always_comb begin
    w_digits[3] = 4'(w_integer_part / 10); // Dígito 3 (MSB): decenas de L/min
    w_digits[2] = 4'(w_integer_part % 10); // Dígito 2: unidades de L/min
    w_digits[1] = 4'(w_frac_decimal / 10); // Dígito 1: décimas de L/min
    w_digits[0] = 4'(w_frac_decimal % 10); // Dígito 0 (LSB): centésimas de L/min
  end

  // ═══════════════════════════════════════════════════════════════════════
  //  Tabla de decodificación BCD → 7 segmentos (activo bajo)
  // ═══════════════════════════════════════════════════════════════════════
  function automatic logic [7:0] bcd_to_seg(input logic [3:0] bcd, input logic dp);
    logic [6:0] seg;                       // Segmentos {g, f, e, d, c, b, a}
    case (bcd)
      4'd0: seg = 7'b100_0000;            // Segmentos: a,b,c,d,e,f ON (muestra "0")
      4'd1: seg = 7'b111_1001;            // Segmentos: b,c ON (muestra "1")
      4'd2: seg = 7'b010_0100;            // Segmentos: a,b,d,e,g ON (muestra "2")
      4'd3: seg = 7'b011_0000;            // Segmentos: a,b,c,d,g ON (muestra "3")
      4'd4: seg = 7'b001_1001;            // Segmentos: b,c,f,g ON (muestra "4")
      4'd5: seg = 7'b001_0010;            // Segmentos: a,c,d,f,g ON (muestra "5")
      4'd6: seg = 7'b000_0010;            // Segmentos: a,c,d,e,f,g ON (muestra "6")
      4'd7: seg = 7'b111_1000;            // Segmentos: a,b,c ON (muestra "7")
      4'd8: seg = 7'b000_0000;            // Segmentos: todos ON (muestra "8")
      4'd9: seg = 7'b001_0000;            // Segmentos: a,b,c,d,f,g ON (muestra "9")
      default: seg = 7'b111_1111;          // Todos OFF: dígito inválido → apagado
    endcase
    return {~dp, seg};                     // Punto decimal invertido (activo bajo) + segmentos
  endfunction

  // ═══════════════════════════════════════════════════════════════════════
  //  Multiplexación de dígitos a ~1 kHz
  // ═══════════════════════════════════════════════════════════════════════
  // Cada dígito se enciende por 1/(REFRESH_HZ × NUM_DIGITS) segundos.
  // A 1 kHz con 4 dígitos: cada dígito brilla 250 μs → persistencia visual OK.

  localparam int MUX_COUNT_MAX = CLK_FREQ / (REFRESH_HZ * NUM_DIGITS) - 1; // Ciclos por slot de dígito
  localparam int MUX_WIDTH     = $clog2(MUX_COUNT_MAX + 1);                // Ancho del contador mux

  logic [MUX_WIDTH-1:0] r_mux_count;      // Contador de ciclos dentro del slot del dígito activo
  logic [1:0]           r_active_digit;    // Índice del dígito activo (0..3, round-robin)

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      r_mux_count    <= '0;                // Reiniciar contador de multiplexación
      r_active_digit <= 2'd0;              // Comenzar por el dígito 0 (centésimas)
    end
    else begin
      if (r_mux_count == MUX_WIDTH'(MUX_COUNT_MAX)) begin
        r_mux_count    <= '0;              // Reiniciar contador: slot de dígito completado
        r_active_digit <= r_active_digit + 2'd1; // Avanzar al siguiente dígito (wraps a 0)
      end
      else begin
        r_mux_count <= r_mux_count + 1'b1; // Incrementar contador dentro del slot actual
      end
    end
  end

  // ═══════════════════════════════════════════════════════════════════════
  //  Salida de segmentos y habilitación del dígito activo
  // ═══════════════════════════════════════════════════════════════════════
  always_comb begin
    // Decodificar el dígito activo a 7 segmentos con punto decimal.
    // Se invierte el orden (~r_active_digit) para que DIG1(r=0) muestre decenas(3)
    // y DIG4(r=3) muestre centésimas(0). Formato XX.XX.
    o_segments = bcd_to_seg(w_digits[~r_active_digit],
                            (r_active_digit == 2'd1)); // DP activo en DIG2 (unidades)

    // Supresión del cero a la izquierda (apagar DIG1 si las decenas son 0)
    if (r_active_digit == 2'd0 && w_digits[3] == 4'd0) begin
      o_segments = 8'b1111_1111; // Todos los segmentos apagados (activo bajo)
    end

    // Habilitación de dígito: activo bajo (solo 1 dígito encendido a la vez).
    o_digit_en = 4'b1111;                  // Todos deshabilitados por defecto
    o_digit_en[r_active_digit] = 1'b0;     // Habilitar solo el dígito activo
  end

endmodule : seven_seg_driver
