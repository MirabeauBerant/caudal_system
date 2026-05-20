//=============================================================================
// fpga_comm.cpp — Implementación de la comunicación UART con FPGA
//=============================================================================

#include "fpga_comm.h"
#include "pulse_gen.h"
#include <math.h>

void FpgaComm::begin(HardwareSerial& serial, int rxPin, int txPin, uint32_t baud) {
    m_serial = &serial;
    m_serial->begin(baud, SERIAL_8N1, rxPin, txPin);
    m_rxCount      = 0;
    m_lastByteMs   = 0;
    m_historyHead  = 0;
    m_historyCount = 0;
    m_totalReadings = 0;
}

void FpgaComm::update() {
    if (!m_serial) return;

    while (m_serial->available()) {
        uint8_t b = m_serial->read();

        // Sincronización por timeout: si pasan >100 ms entre bytes,
        // el segundo byte probablemente pertenece a otra trama → reiniciar.
        if (millis() - m_lastByteMs > 100) {
            m_rxCount = 0;
        }
        m_lastByteMs = millis();

        m_rxBuffer[m_rxCount++] = b;

        if (m_rxCount >= 2) {
            // Decodificar trama completa: [MSB][LSB] → Q8.8 unsigned.
            uint16_t raw = ((uint16_t)m_rxBuffer[0] << 8) | m_rxBuffer[1];
            pushReading(raw);
            m_rxCount = 0;
        }
    }
}

FpgaReading FpgaComm::getLatest() const {
    if (m_historyCount == 0) {
        return {0, 0.0f, 0, false};
    }
    int idx = (m_historyHead - 1 + HISTORY_SIZE) % HISTORY_SIZE;
    return m_history[idx];
}

FpgaReading FpgaComm::getHistory(int index) const {
    if (index < 0 || index >= m_historyCount) {
        return {0, 0.0f, 0, false};
    }
    int idx = (m_historyHead - 1 - index + HISTORY_SIZE * 2) % HISTORY_SIZE;
    return m_history[idx];
}

void FpgaComm::clearHistory() {
    m_historyHead  = 0;
    m_historyCount = 0;
    m_rxCount      = 0;
}

bool FpgaComm::waitForReading(uint32_t timeoutMs) {
    uint32_t countBefore = m_totalReadings;
    uint32_t start = millis();
    while ((millis() - start) < timeoutMs) {
        update();
        if (m_totalReadings > countBefore) {
            return true;
        }
        delay(1);  // Ceder CPU brevemente.
    }
    return false;
}

bool FpgaComm::waitForReadingWithPulses(PulseGenerator& gen, uint32_t timeoutMs) {
    uint32_t countBefore = m_totalReadings;
    uint32_t start = millis();
    while ((millis() - start) < timeoutMs) {
        gen.update();
        update();
        if (m_totalReadings > countBefore) {
            return true;
        }
    }
    return false;
}

float FpgaComm::getAverage(int numSamples) const {
    int count = min(numSamples, m_historyCount);
    if (count == 0) return 0.0f;

    float sum = 0.0f;
    for (int i = 0; i < count; i++) {
        sum += getHistory(i).flowLmin;
    }
    return sum / (float)count;
}

float FpgaComm::getStdDev(int numSamples) const {
    int count = min(numSamples, m_historyCount);
    if (count < 2) return 0.0f;

    float avg = getAverage(count);
    float sumSq = 0.0f;
    for (int i = 0; i < count; i++) {
        float diff = getHistory(i).flowLmin - avg;
        sumSq += diff * diff;
    }
    return sqrtf(sumSq / (float)(count - 1));
}

void FpgaComm::pushReading(uint16_t raw) {
    FpgaReading reading;
    reading.raw         = raw;
    reading.flowLmin    = q88ToFloat(raw);
    reading.timestampMs = millis();
    reading.valid       = true;

    m_history[m_historyHead] = reading;
    m_historyHead = (m_historyHead + 1) % HISTORY_SIZE;
    if (m_historyCount < HISTORY_SIZE) {
        m_historyCount++;
    }
    m_totalReadings++;
}
