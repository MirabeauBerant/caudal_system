//=============================================================================
// pulse_gen.h — Generador de Pulsos con Inyección de Fallas
//
// Simula la señal de salida del sensor YF-S201 con soporte para:
//   - Frecuencia precisa basada en caudal (L/min)
//   - Inyección de rebotes mecánicos (bounce)
//   - Omisión de pulsos (dropout)
//   - Jitter temporal aleatorio
//=============================================================================

#pragma once
#include <Arduino.h>
#include "config.h"

class PulseGenerator {
public:
    /// Inicializar el generador en el pin de salida.
    void begin(int pin = PIN_PULSE_OUT);

    /// Establecer caudal en L/min → calcula frecuencia automáticamente.
    void setFlowRate(float lmin);

    /// Establecer frecuencia directamente en Hz.
    void setFrequency(float hz);

    /// Detener la generación de pulsos (línea baja).
    void stop();

    /// Llamar en cada iteración de loop() para generar pulsos.
    void update();

    // ── Getters ──
    float    getFlowRate()  const { return m_flowRate; }
    float    getFrequency() const { return m_frequency; }
    bool     isRunning()    const { return m_running; }

    // ── Inyección de fallas ──

    /// Simular rebote mecánico: numBounces toggles rápidos de bounceWidthUs μs.
    void enableBounce(int numBounces, uint32_t bounceWidthUs);
    void disableBounce();

    /// Omitir 1 de cada skipEveryN pulsos.
    void enableDropout(int skipEveryN);
    void disableDropout();

    /// Agregar jitter aleatorio de hasta ±maxJitterUs μs a cada pulso.
    void enableJitter(uint32_t maxJitterUs);
    void disableJitter();

    /// Desactivar todas las fallas.
    void clearAllFaults();

private:
    int      m_pin           = PIN_PULSE_OUT;
    float    m_flowRate      = 0.0f;
    float    m_frequency     = 0.0f;
    uint32_t m_halfPeriodUs  = 0;
    uint32_t m_lastToggleUs  = 0;
    bool     m_pulseState    = false;
    bool     m_running       = false;

    // Bounce
    bool     m_bounceEnabled  = false;
    int      m_numBounces     = 0;
    uint32_t m_bounceWidthUs  = 0;
    int      m_bounceRemaining = 0;
    uint32_t m_bounceNextUs   = 0;
    bool     m_inBounce       = false;

    // Dropout
    bool     m_dropoutEnabled = false;
    int      m_skipEveryN     = 0;
    int      m_pulseCount     = 0;

    // Jitter
    bool     m_jitterEnabled  = false;
    uint32_t m_maxJitterUs    = 0;

    void togglePin();
    uint32_t getJitteredPeriod();
};
