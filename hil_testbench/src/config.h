//=============================================================================
// config.h — Configuración global del Banco de Pruebas HIL
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Módulo   : Banco HIL (ESP32 XX5R69)
//
// Define pines, constantes de calibración del sensor YF-S201, parámetros
// de temporización del pipeline FPGA y umbrales de verificación.
//=============================================================================

#pragma once
#include <Arduino.h>

// ═══════════════════════════════════════════════════════════════════════════
//  ASIGNACIÓN DE PINES — Conexiones ESP32 ↔ FPGA
// ═══════════════════════════════════════════════════════════════════════════

// ESP32 → FPGA (estímulo)
constexpr int PIN_PULSE_OUT    = 25;   // GPIO25 → FPGA PIN_119 (i_sensor)

// FPGA → ESP32 (telemetría UART)
constexpr int PIN_FPGA_UART_RX = 16;   // GPIO16 (Serial2 RX) ← FPGA PIN_118 (o_uart_tx)
constexpr int PIN_FPGA_UART_TX = 17;   // GPIO17 (Serial2 TX) — no utilizado por la FPGA

// FPGA → ESP32 (diagnóstico digital, opcional)
constexpr int PIN_STATUS_OK    = 26;   // GPIO26 ← FPGA status OK
constexpr int PIN_STATUS_WARN  = 27;   // GPIO27 ← FPGA status WARN
constexpr int PIN_STATUS_ALERT = 14;   // GPIO14 ← FPGA status ALERT

// ═══════════════════════════════════════════════════════════════════════════
//  CONSTANTES DE CALIBRACIÓN — Sensor YF-S201
// ═══════════════════════════════════════════════════════════════════════════

constexpr float PULSES_PER_LITER_MIN = 7.5f;  // F(Hz) = 7.5 × Q(L/min)
constexpr float FLOW_MIN_LMIN        = 1.0f;  // Rango mínimo del sensor
constexpr float FLOW_MAX_LMIN        = 30.0f; // Rango máximo del sensor
constexpr float FREQ_AT_MIN          = FLOW_MIN_LMIN * PULSES_PER_LITER_MIN;  //  7.5 Hz
constexpr float FREQ_AT_MAX          = FLOW_MAX_LMIN * PULSES_PER_LITER_MIN;  // 225.0 Hz

// ═══════════════════════════════════════════════════════════════════════════
//  CONSTANTES Q8.8 — Representación en punto fijo de la FPGA
// ═══════════════════════════════════════════════════════════════════════════

constexpr uint16_t Q88_ZERO      = 0x0000;  //  0.00 L/min
constexpr uint16_t Q88_ONE       = 0x0100;  //  1.00 L/min (256)
constexpr uint16_t Q88_THIRTY    = 0x1E00;  // 30.00 L/min (7680)

// ═══════════════════════════════════════════════════════════════════════════
//  TEMPORIZACIÓN DEL PIPELINE FPGA
// ═══════════════════════════════════════════════════════════════════════════

// El freq_counter muestrea en ventanas de 1 segundo.
constexpr uint32_t FPGA_SAMPLE_PERIOD_MS  = 1000;

// El filtro EMA con α=1/8 necesita ~8 muestras para asentar al 63%.
// Usamos 12 muestras (~12s) para >95% de asentamiento.
constexpr uint32_t EMA_SETTLE_SAMPLES     = 12;

// Tiempo default de espera para estabilización del pipeline completo.
constexpr uint32_t DEFAULT_SETTLE_MS      = (EMA_SETTLE_SAMPLES * FPGA_SAMPLE_PERIOD_MS) + 3000;

// Tiempo corto de espera (modo rápido, sin EMA completo).
constexpr uint32_t QUICK_SETTLE_MS        = 5000;

// ═══════════════════════════════════════════════════════════════════════════
//  UMBRALES DE VERIFICACIÓN
// ═══════════════════════════════════════════════════════════════════════════

// Tolerancia default para verificación de caudal (L/min).
constexpr float DEFAULT_TOLERANCE_LMIN    = 0.50f;

// Tolerancia estricta para pruebas de topes y zona muerta.
constexpr float STRICT_TOLERANCE_LMIN     = 0.15f;

// ═══════════════════════════════════════════════════════════════════════════
//  UART
// ═══════════════════════════════════════════════════════════════════════════

constexpr uint32_t FPGA_BAUD_RATE   = 115200;
constexpr uint32_t SERIAL_BAUD_RATE = 115200;
