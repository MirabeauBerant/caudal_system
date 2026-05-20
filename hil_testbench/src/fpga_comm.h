//=============================================================================
// fpga_comm.h — Comunicación UART con la FPGA
//
// Recibe tramas de 2 bytes (MSB, LSB) en formato Q8.8 enviadas por la FPGA
// cada segundo. Mantiene un buffer circular de lecturas históricas y calcula
// estadísticas (promedio, desviación estándar) para verificación automatizada.
//=============================================================================

#pragma once
#include <Arduino.h>
#include "config.h"

/// Estructura de una lectura individual de la FPGA.
struct FpgaReading {
    uint16_t raw;          // Valor crudo Q8.8 (MSB << 8 | LSB)
    float    flowLmin;     // Caudal decodificado en L/min
    uint32_t timestampMs;  // Tiempo de recepción (millis())
    bool     valid;        // true si la lectura fue decodificada correctamente
};

class FpgaComm {
public:
    static constexpr int HISTORY_SIZE = 32;

    /// Inicializar UART2 para recibir datos de la FPGA.
    void begin(HardwareSerial& serial = Serial2,
               int rxPin  = PIN_FPGA_UART_RX,
               int txPin  = PIN_FPGA_UART_TX,
               uint32_t baud = FPGA_BAUD_RATE);

    /// Llamar en cada iteración de loop() para procesar bytes entrantes.
    void update();

    /// Obtener la lectura más reciente.
    FpgaReading getLatest() const;

    /// Obtener lectura del historial (0 = más reciente, 1 = anterior, ...).
    FpgaReading getHistory(int index) const;

    /// Número de lecturas almacenadas en el historial.
    int getHistoryCount() const { return m_historyCount; }

    /// Limpiar el buffer de historial.
    void clearHistory();

    /// Esperar bloqueante hasta recibir una nueva lectura (con timeout).
    /// Retorna true si se recibió una lectura, false si expiró el timeout.
    /// NOTA: Llama internamente a update(), pero el caller debe llamar
    /// pulseGen.update() externamente si necesita seguir generando pulsos.
    bool waitForReading(uint32_t timeoutMs = 2000);

    /// Esperar bloqueante con generación de pulsos activa.
    /// Requiere referencia al PulseGenerator para mantenerlo activo.
    bool waitForReadingWithPulses(class PulseGenerator& gen, uint32_t timeoutMs = 2000);

    // ── Estadísticas ──

    /// Promedio de las últimas numSamples lecturas (L/min).
    float getAverage(int numSamples = 5) const;

    /// Desviación estándar de las últimas numSamples lecturas (L/min).
    float getStdDev(int numSamples = 5) const;

    /// Contador total de lecturas recibidas desde begin().
    uint32_t getTotalReadings() const { return m_totalReadings; }

    // ── Conversión Q8.8 ──
    static float q88ToFloat(uint16_t raw) { return raw / 256.0f; }
    static uint16_t floatToQ88(float lmin) { return (uint16_t)(lmin * 256.0f); }

private:
    HardwareSerial* m_serial = nullptr;

    // Máquina de estados de recepción UART.
    uint8_t  m_rxBuffer[2];
    uint8_t  m_rxCount     = 0;
    uint32_t m_lastByteMs  = 0;

    // Buffer circular de historial.
    FpgaReading m_history[HISTORY_SIZE];
    int      m_historyHead  = 0;
    int      m_historyCount = 0;
    uint32_t m_totalReadings = 0;

    void pushReading(uint16_t raw);
};
