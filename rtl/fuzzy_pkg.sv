//=============================================================================
// fuzzy_pkg.sv — Paquete global para el controlador difuso Takagi-Sugeno
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Curso    : Sistemas Electrónicos (EL215BLI) — UNSAAC
// Target   : Intel MAX 10 (10M08SCE144C8G) · 50 MHz
//
// Descripción:
//   Define constantes, tipos y parámetros de aritmética en punto fijo
//   para el motor difuso completo. Todos los módulos (fuzzifier,
//   rule_base, defuzzifier) importan este paquete para garantizar
//   coherencia en anchos de bus y breakpoints de membresía.
//
// Aritmética:
//   - Entradas crisp:  Punto fijo con signo (signed)
//   - Grados de membresía: 8 bits unsigned [0..255] donde 255 = 1.0
//   - Salidas Takagi-Sugeno: signed 16 bits
//=============================================================================

package fuzzy_pkg;

  // ═══════════════════════════════════════════════════════════════════════
  //  PARÁMETROS GLOBALES
  // ═══════════════════════════════════════════════════════════════════════

  // Ancho de las entradas crisp (signed)
  localparam int INPUT_WIDTH  = 16;   // Q8.8 punto fijo con signo

  // Ancho de grados de membresía (unsigned, 0–255 → 0.0–1.0)
  localparam int MU_WIDTH     = 8;

  // Ancho de la salida de corrección (signed)
  localparam int OUTPUT_WIDTH = 16;

  // Resolución máxima del grado de membresía
  localparam logic [MU_WIDTH-1:0] MU_MAX = 8'hFF;  // 255 = 1.0


  // ═══════════════════════════════════════════════════════════════════════
  //  CONJUNTOS DIFUSOS — Error de Flujo (ΔQ)
  // ═══════════════════════════════════════════════════════════════════════
  //
  //  5 conjuntos triangulares simétricos:
  //    NB (Negativo Grande), NS (Negativo Pequeño), ZE (Cero),
  //    PS (Positivo Pequeño), PB (Positivo Grande)
  //
  //  Dominio: [-128, +127] en Q8.8 → [-32768, +32512]
  //  Pero usamos valores escalados para breakpoints razonables.

  localparam int NUM_SETS_ERROR = 5;

  // Índices de conjuntos difusos para el Error
  typedef enum logic [2:0] {
    ERR_NB = 3'd0,
    ERR_NS = 3'd1,
    ERR_ZE = 3'd2,
    ERR_PS = 3'd3,
    ERR_PB = 3'd4
  } error_set_e;

  // Breakpoints de funciones triangulares para Error (en Q8.8)
  // Cada triang: [left, center, right]
  // Valores en unidades de punto fijo Q8.8 (multiply by 256)
  //   -80, -40, -20, 0, +20, +40, +80 como centros razonables
  //   Escalados a Q8.8: valor * 256

  // Breakpoints: {left, center, right} para cada conjunto
  // Error en pulsos/seg desviación. Rango práctico ~ ±100 pulsos
  typedef logic signed [INPUT_WIDTH-1:0] bp_error_t [NUM_SETS_ERROR][3];
  localparam bp_error_t ERR_BP = '{
    // NB: (-128, -80, -40) — saturación izquierda
    '{-16'sd128, -16'sd80, -16'sd40},
    // NS: (-80, -40, 0)
    '{-16'sd80,  -16'sd40,  16'sd0},
    // ZE: (-40, 0, +40)
    '{-16'sd40,   16'sd0,   16'sd40},
    // PS: (0, +40, +80)
    '{ 16'sd0,   16'sd40,   16'sd80},
    // PB: (+40, +80, +128) — saturación derecha
    '{ 16'sd40,  16'sd80,   16'sd128}
  };


  // ═══════════════════════════════════════════════════════════════════════
  //  CONJUNTOS DIFUSOS — Derivada del Caudal (dQ/dt)
  // ═══════════════════════════════════════════════════════════════════════
  //
  //  3 conjuntos triangulares: NEG, ZERO, POS

  localparam int NUM_SETS_DERIV = 3;

  typedef enum logic [1:0] {
    DRV_NEG  = 2'd0,
    DRV_ZERO = 2'd1,
    DRV_POS  = 2'd2
  } deriv_set_e;

  // Breakpoints para Derivada
  typedef logic signed [INPUT_WIDTH-1:0] bp_deriv_t [NUM_SETS_DERIV][3];
  localparam bp_deriv_t DRV_BP = '{
    // NEG: (-64, -32, 0)
    '{-16'sd64, -16'sd32,  16'sd0},
    // ZERO: (-32, 0, +32)
    '{-16'sd32,  16'sd0,   16'sd32},
    // POS: (0, +32, +64)
    '{ 16'sd0,   16'sd32,  16'sd64}
  };


  // ═══════════════════════════════════════════════════════════════════════
  //  REGLAS DIFUSAS — Matriz 5×3 Takagi-Sugeno
  // ═══════════════════════════════════════════════════════════════════════
  //
  //  Consecuentes: valores de corrección crisp (signed 16-bit)
  //  Convención: positivo = incrementar caudal medido, negativo = decrementar
  //
  //           dQ/dt:   NEG     ZERO     POS
  //  Error NB:       +50      +40      +25
  //  Error NS:       +25      +15       0
  //  Error ZE:       +10        0      -10
  //  Error PS:         0      -15      -25
  //  Error PB:       -25      -40      -50

  localparam int NUM_RULES = NUM_SETS_ERROR * NUM_SETS_DERIV;  // 15

  // Consecuentes Takagi-Sugeno (constantes, primer orden simplificado)
  typedef logic signed [OUTPUT_WIDTH-1:0] ts_conseq_t [NUM_SETS_ERROR][NUM_SETS_DERIV];
  localparam ts_conseq_t TS_CONSEQUENT = '{
    // Error NB ×  {NEG,   ZERO,   POS}
    '{ 16'sd50,  16'sd40,  16'sd25},
    // Error NS
    '{ 16'sd25,  16'sd15,  16'sd0},
    // Error ZE
    '{ 16'sd10,  16'sd0,  -16'sd10},
    // Error PS
    '{ 16'sd0,  -16'sd15, -16'sd25},
    // Error PB
    '{-16'sd25, -16'sd40, -16'sd50}
  };


  // ═══════════════════════════════════════════════════════════════════════
  //  TIPOS DE DATOS COMPUESTOS
  // ═══════════════════════════════════════════════════════════════════════

  // Vector de grados de membresía para Error (5 conjuntos)
  typedef logic [MU_WIDTH-1:0] mu_error_t [NUM_SETS_ERROR];

  // Vector de grados de membresía para Derivada (3 conjuntos)
  typedef logic [MU_WIDTH-1:0] mu_deriv_t [NUM_SETS_DERIV];

  // Estructura de resultado de una regla individual
  typedef struct packed {
    logic [MU_WIDTH-1:0]         firing_strength;   // min(μ_err, μ_drv)
    logic signed [OUTPUT_WIDTH-1:0] consequent;      // z_i (valor T-S)
  } rule_result_t;

endpackage : fuzzy_pkg
