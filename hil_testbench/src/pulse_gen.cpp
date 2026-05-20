//=============================================================================
// pulse_gen.cpp — Implementación del Generador de Pulsos
//=============================================================================

#include "pulse_gen.h"

void PulseGenerator::begin(int pin) {
    m_pin = pin;
    pinMode(m_pin, OUTPUT);
    digitalWrite(m_pin, LOW);
    m_pulseState   = false;
    m_running      = false;
    m_lastToggleUs = micros();
    clearAllFaults();
}

void PulseGenerator::setFlowRate(float lmin) {
    m_flowRate = lmin;
    if (lmin <= 0.0f) {
        stop();
        return;
    }
    setFrequency(lmin * PULSES_PER_LITER_MIN);
}

void PulseGenerator::setFrequency(float hz) {
    if (hz <= 0.0f) {
        stop();
        return;
    }
    m_frequency    = hz;
    // Medio período: cada toggle alterna HIGH/LOW → 2 toggles = 1 ciclo completo.
    m_halfPeriodUs = (uint32_t)(1000000.0f / (hz * 2.0f));
    m_running      = true;
    m_lastToggleUs = micros();
}

void PulseGenerator::stop() {
    m_running    = false;
    m_frequency  = 0.0f;
    m_flowRate   = 0.0f;
    m_pulseState = false;
    m_inBounce   = false;
    digitalWrite(m_pin, LOW);
}

void PulseGenerator::update() {
    if (!m_running) return;

    uint32_t now = micros();

    // ── Procesamiento de rebotes activos ──
    if (m_inBounce) {
        if ((now - m_bounceNextUs) >= m_bounceWidthUs) {
            togglePin();
            m_bounceRemaining--;
            m_bounceNextUs = now;
            if (m_bounceRemaining <= 0) {
                m_inBounce = false;
                // Asegurar que el pin quede en el estado correcto del pulso real.
                digitalWrite(m_pin, m_pulseState ? HIGH : LOW);
            }
        }
        return;  // Durante un bounce no procesamos el pulso principal.
    }

    // ── Generación del pulso principal ──
    uint32_t period = getJitteredPeriod();
    if ((now - m_lastToggleUs) >= period) {
        m_lastToggleUs = now;

        // Verificar dropout: omitir este toggle si corresponde.
        if (m_dropoutEnabled) {
            m_pulseCount++;
            if ((m_pulseCount % m_skipEveryN) == 0) {
                return;  // Saltar este pulso (simular fallo del sensor).
            }
        }

        // Toggle normal.
        m_pulseState = !m_pulseState;
        digitalWrite(m_pin, m_pulseState ? HIGH : LOW);

        // Iniciar secuencia de bounce si está habilitada y es un flanco ascendente.
        if (m_bounceEnabled && m_pulseState) {
            m_inBounce        = true;
            m_bounceRemaining = m_numBounces * 2;  // Cada bounce = toggle+toggle.
            m_bounceNextUs    = now;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Inyección de fallas
// ═══════════════════════════════════════════════════════════════════════════

void PulseGenerator::enableBounce(int numBounces, uint32_t bounceWidthUs) {
    m_bounceEnabled = true;
    m_numBounces    = numBounces;
    m_bounceWidthUs = bounceWidthUs;
}

void PulseGenerator::disableBounce() {
    m_bounceEnabled = false;
    m_inBounce      = false;
}

void PulseGenerator::enableDropout(int skipEveryN) {
    m_dropoutEnabled = true;
    m_skipEveryN     = max(skipEveryN, 2);  // Mínimo: saltar 1 de cada 2.
    m_pulseCount     = 0;
}

void PulseGenerator::disableDropout() {
    m_dropoutEnabled = false;
}

void PulseGenerator::enableJitter(uint32_t maxJitterUs) {
    m_jitterEnabled = true;
    m_maxJitterUs   = maxJitterUs;
}

void PulseGenerator::disableJitter() {
    m_jitterEnabled = false;
}

void PulseGenerator::clearAllFaults() {
    disableBounce();
    disableDropout();
    disableJitter();
}

// ═══════════════════════════════════════════════════════════════════════════
//  Funciones internas
// ═══════════════════════════════════════════════════════════════════════════

void PulseGenerator::togglePin() {
    m_pulseState = !m_pulseState;
    digitalWrite(m_pin, m_pulseState ? HIGH : LOW);
}

uint32_t PulseGenerator::getJitteredPeriod() {
    if (!m_jitterEnabled || m_maxJitterUs == 0) {
        return m_halfPeriodUs;
    }
    // Jitter aleatorio uniforme: ±maxJitterUs.
    int32_t jitter = (int32_t)random(0, m_maxJitterUs * 2 + 1) - (int32_t)m_maxJitterUs;
    int32_t result = (int32_t)m_halfPeriodUs + jitter;
    return (result > 0) ? (uint32_t)result : 1;
}
