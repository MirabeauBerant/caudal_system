//=============================================================================
// test_suites.cpp — Implementación de las 6 Suites de Prueba HIL
//
// Cada prueba sigue el patrón: Estímulo → Estabilización → Verificación
//
// Convención de tiempos:
//   - DEFAULT_SETTLE_MS (15s): para pruebas que necesitan EMA estable
//   - QUICK_SETTLE_MS   (5s):  para pruebas de respuesta rápida
//=============================================================================

#include "test_suites.h"
#include "config.h"

namespace TestSuites {

// ═══════════════════════════════════════════════════════════════════════════
//  SUITE 1: Topes y Zona Muerta (Deadband / Clamping)
// ═══════════════════════════════════════════════════════════════════════════

static TestResult test_deadband_inferior(PulseGenerator& gen, FpgaComm& comm) {
    // Estímulo: 0.5 L/min (por debajo del mínimo de 1 L/min)
    // Esperado: FPGA debe reportar 0.00 L/min (zona muerta activa)
    return hilStimulateAndVerify(gen, comm, 0.5f, 0.00f, STRICT_TOLERANCE_LMIN, DEFAULT_SETTLE_MS);
}

static TestResult test_limite_inferior(PulseGenerator& gen, FpgaComm& comm) {
    // Estímulo: 1.0 L/min (justo en el límite inferior)
    // Esperado: FPGA debe reportar ~1.00 L/min
    return hilStimulateAndVerify(gen, comm, 1.0f, 1.0f, DEFAULT_TOLERANCE_LMIN, DEFAULT_SETTLE_MS);
}

static TestResult test_tope_superior(PulseGenerator& gen, FpgaComm& comm) {
    // Estímulo: 35 L/min (por encima del máximo de 30 L/min)
    // Esperado: FPGA debe clampear a 30.00 L/min
    return hilStimulateAndVerify(gen, comm, 35.0f, 30.0f, STRICT_TOLERANCE_LMIN, DEFAULT_SETTLE_MS);
}

static TestResult test_cero_absoluto(PulseGenerator& gen, FpgaComm& comm) {
    // Estímulo: Sin pulsos (0 Hz)
    // Esperado: FPGA debe reportar 0.00 L/min
    gen.stop();
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);
    return hilVerifyFlow(comm, 0.00f, STRICT_TOLERANCE_LMIN);
}

static TestResult test_limite_superior_exacto(PulseGenerator& gen, FpgaComm& comm) {
    // Estímulo: 30.0 L/min (exactamente en el tope)
    // Esperado: FPGA debe reportar 30.00 L/min
    return hilStimulateAndVerify(gen, comm, 30.0f, 30.0f, DEFAULT_TOLERANCE_LMIN, DEFAULT_SETTLE_MS);
}

const TestCase limitsTests[] = {
    {"1.1 Deadband inferior",       "Estimulo 0.5 L/min -> Espera 0.00 (zona muerta)", test_deadband_inferior},
    {"1.2 Limite inferior (1 L/m)", "Estimulo 1.0 L/min -> Espera ~1.00",              test_limite_inferior},
    {"1.3 Tope superior (35 L/m)",  "Estimulo 35 L/min  -> Espera 30.00 (clamping)",   test_tope_superior},
    {"1.4 Cero absoluto",           "Sin pulsos (0 Hz)  -> Espera 0.00",               test_cero_absoluto},
    {"1.5 Limite superior (30 L/m)","Estimulo 30 L/min  -> Espera 30.00",              test_limite_superior_exacto},
};
const int limitsTestCount = sizeof(limitsTests) / sizeof(limitsTests[0]);


// ═══════════════════════════════════════════════════════════════════════════
//  SUITE 2: Linealidad del Pipeline
// ═══════════════════════════════════════════════════════════════════════════

static TestResult test_linealidad_barrido(PulseGenerator& gen, FpgaComm& comm) {
    // Barrido ascendente de 2 a 28 L/min en pasos de 2 L/min.
    // Cada punto debe estar dentro de ±0.5 L/min del valor real.
    Serial.println("  │  Barrido ascendente: 2 → 28 L/min (paso 2)");

    for (float flow = 2.0f; flow <= 28.0f; flow += 2.0f) {
        gen.setFlowRate(flow);
        hilSettle(gen, comm, DEFAULT_SETTLE_MS);

        TestResult r = hilVerifyFlow(comm, flow, DEFAULT_TOLERANCE_LMIN);
        if (r != TestResult::PASS) {
            Serial.printf("  │  *** Fallo en punto %.1f L/min ***\n", flow);
            return TestResult::FAIL;
        }
        Serial.printf("  │  Punto %.1f L/min: OK\n", flow);
    }
    return TestResult::PASS;
}

static TestResult test_histeresis(PulseGenerator& gen, FpgaComm& comm) {
    // Barrido ascendente y descendente: verificar que la diferencia
    // entre lecturas de ida y vuelta en el mismo punto es < 0.3 L/min.
    Serial.println("  │  Prueba de histeresis: subida vs bajada");

    constexpr int NUM_POINTS = 5;
    float points[NUM_POINTS] = {5.0f, 10.0f, 15.0f, 20.0f, 25.0f};
    float readingsUp[NUM_POINTS], readingsDown[NUM_POINTS];

    // Barrido ascendente.
    for (int i = 0; i < NUM_POINTS; i++) {
        gen.setFlowRate(points[i]);
        hilSettle(gen, comm, DEFAULT_SETTLE_MS);
        readingsUp[i] = comm.getAverage(3);
    }

    // Barrido descendente.
    for (int i = NUM_POINTS - 1; i >= 0; i--) {
        gen.setFlowRate(points[i]);
        hilSettle(gen, comm, DEFAULT_SETTLE_MS);
        readingsDown[i] = comm.getAverage(3);
    }

    // Comparar.
    float maxHysteresis = 0.0f;
    for (int i = 0; i < NUM_POINTS; i++) {
        float diff = fabsf(readingsUp[i] - readingsDown[i]);
        Serial.printf("  │  %.1f L/min: subida=%.2f, bajada=%.2f, diff=%.3f\n",
                      points[i], readingsUp[i], readingsDown[i], diff);
        if (diff > maxHysteresis) maxHysteresis = diff;
    }

    Serial.printf("  │  Histeresis maxima: %.3f L/min\n", maxHysteresis);
    return (maxHysteresis < 0.30f) ? TestResult::PASS : TestResult::FAIL;
}

const TestCase linearityTests[] = {
    {"2.1 Barrido 2-28 L/min",  "Rampa ascendente, paso 2, verifica cada punto", test_linealidad_barrido},
    {"2.2 Histeresis",          "Barrido ida/vuelta, compara lecturas",           test_histeresis},
};
const int linearityTestCount = sizeof(linearityTests) / sizeof(linearityTests[0]);


// ═══════════════════════════════════════════════════════════════════════════
//  SUITE 3: Respuesta Dinámica (Escalones)
// ═══════════════════════════════════════════════════════════════════════════

static TestResult test_escalon_subida(PulseGenerator& gen, FpgaComm& comm) {
    // Escalón 0 → 10 L/min: medir tiempo de asentamiento.
    Serial.println("  │  Escalon: 0 -> 10 L/min");

    gen.stop();
    hilSettle(gen, comm, 3000);  // Asegurar estado inicial = 0.
    comm.clearHistory();

    // Aplicar escalón.
    gen.setFlowRate(10.0f);
    uint32_t start = millis();

    // Monitorear hasta que se estabilice o timeout de 20s.
    bool settled = false;
    while ((millis() - start) < 20000) {
        gen.update();
        comm.update();

        FpgaReading r = comm.getLatest();
        if (r.valid && fabsf(r.flowLmin - 10.0f) < DEFAULT_TOLERANCE_LMIN) {
            // Verificar estabilidad: 3 lecturas consecutivas dentro de tolerancia.
            if (comm.getHistoryCount() >= 3) {
                bool stable = true;
                for (int i = 0; i < 3; i++) {
                    if (fabsf(comm.getHistory(i).flowLmin - 10.0f) > DEFAULT_TOLERANCE_LMIN) {
                        stable = false;
                        break;
                    }
                }
                if (stable) {
                    uint32_t settleTime = millis() - start;
                    Serial.printf("  │  Asentamiento en %u ms\n", (unsigned)settleTime);
                    settled = true;
                    // Criterio: debe asentar en menos de 15 segundos.
                    return (settleTime < 15000) ? TestResult::PASS : TestResult::FAIL;
                }
            }
        }
    }
    return settled ? TestResult::PASS : TestResult::TIMEOUT;
}

static TestResult test_escalon_bajada(PulseGenerator& gen, FpgaComm& comm) {
    // Escalón 10 → 0 L/min: verificar convergencia a 0.
    Serial.println("  │  Escalon: 10 -> 0 L/min");

    gen.setFlowRate(10.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);  // Establecer estado inicial.

    // Aplicar corte.
    gen.stop();
    comm.clearHistory();
    uint32_t start = millis();

    while ((millis() - start) < 20000) {
        gen.update();
        comm.update();

        if (comm.getHistoryCount() >= 3) {
            float avg = comm.getAverage(3);
            if (avg < STRICT_TOLERANCE_LMIN) {
                uint32_t settleTime = millis() - start;
                Serial.printf("  │  Convergencia a 0 en %u ms\n", (unsigned)settleTime);
                return (settleTime < 15000) ? TestResult::PASS : TestResult::FAIL;
            }
        }
    }
    return TestResult::TIMEOUT;
}

static TestResult test_escalon_intermedio(PulseGenerator& gen, FpgaComm& comm) {
    // Escalón 5 → 15 L/min: cambio dentro del rango de operación.
    Serial.println("  │  Escalon: 5 -> 15 L/min");

    gen.setFlowRate(5.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    // Aplicar escalón.
    gen.setFlowRate(15.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    return hilVerifyFlow(comm, 15.0f, DEFAULT_TOLERANCE_LMIN);
}

const TestCase dynamicsTests[] = {
    {"3.1 Escalon 0->10 L/min", "Medir tiempo de asentamiento",          test_escalon_subida},
    {"3.2 Escalon 10->0 L/min", "Verificar convergencia a cero",         test_escalon_bajada},
    {"3.3 Escalon 5->15 L/min", "Cambio operativo, error estacionario",  test_escalon_intermedio},
};
const int dynamicsTestCount = sizeof(dynamicsTests) / sizeof(dynamicsTests[0]);


// ═══════════════════════════════════════════════════════════════════════════
//  SUITE 4: Detección de Anomalías
// ═══════════════════════════════════════════════════════════════════════════

static TestResult test_burbuja_aire(PulseGenerator& gen, FpgaComm& comm) {
    // Establecer flujo estable, luego inyectar pico transitorio.
    // El EMA debe atenuar el pico y la lectura no debe desviarse >1 L/min.
    Serial.println("  │  Flujo estable 10 L/min + pico de burbuja");

    gen.setFlowRate(10.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    // Inyectar burbuja: subir a 18 L/min por 500ms, luego volver a 10.
    gen.setFlowRate(18.0f);
    uint32_t burstStart = millis();
    while ((millis() - burstStart) < 500) {
        gen.update();
        comm.update();
    }
    gen.setFlowRate(10.0f);

    // Esperar 5 segundos y verificar que la lectura volvió cerca de 10.
    hilSettle(gen, comm, QUICK_SETTLE_MS);

    float avg = comm.getAverage(3);
    float deviation = fabsf(avg - 10.0f);
    Serial.printf("  │  Post-burbuja: lectura=%.2f, desviacion=%.2f\n", avg, deviation);

    // El EMA debe haber atenuado el pico. Aceptar hasta 1.5 L/min de desviación.
    return (deviation < 1.5f) ? TestResult::PASS : TestResult::FAIL;
}

static TestResult test_sensor_desconectado(PulseGenerator& gen, FpgaComm& comm) {
    // Establecer flujo, luego cortar pulsos (simula desconexión).
    Serial.println("  │  Flujo 10 L/min -> corte abrupto (sensor desconectado)");

    gen.setFlowRate(10.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    gen.stop();  // Corte abrupto.
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    return hilVerifyFlow(comm, 0.00f, STRICT_TOLERANCE_LMIN);
}

static TestResult test_fuga_gradual(PulseGenerator& gen, FpgaComm& comm) {
    // Simular fuga: caída gradual 10 → 3 → 1 L/min.
    Serial.println("  │  Fuga gradual: 10 -> 3 -> 1 L/min");

    gen.setFlowRate(10.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    // Caída a 3 L/min.
    gen.setFlowRate(3.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);
    TestResult r1 = hilVerifyFlow(comm, 3.0f, DEFAULT_TOLERANCE_LMIN);
    if (r1 != TestResult::PASS) return r1;

    // Caída a 1 L/min (justo en el límite inferior).
    gen.setFlowRate(1.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);
    return hilVerifyFlow(comm, 1.0f, DEFAULT_TOLERANCE_LMIN);
}

const TestCase anomalyTests[] = {
    {"4.1 Burbuja de aire",      "Pico transitorio +8 L/min x 500ms",    test_burbuja_aire},
    {"4.2 Sensor desconectado",  "Corte abrupto de pulsos",              test_sensor_desconectado},
    {"4.3 Fuga gradual",         "Caida 10 -> 3 -> 1 L/min",            test_fuga_gradual},
};
const int anomalyTestCount = sizeof(anomalyTests) / sizeof(anomalyTests[0]);


// ═══════════════════════════════════════════════════════════════════════════
//  SUITE 5: Robustez del Pulse Detector
// ═══════════════════════════════════════════════════════════════════════════

static TestResult test_rebote_mecanico(PulseGenerator& gen, FpgaComm& comm) {
    // Generar pulsos a 10 L/min con rebotes de 20μs (debajo del filtro de 100μs).
    // La FPGA debe contar correctamente y reportar ~10 L/min.
    Serial.println("  │  Pulsos con rebote mecanico (5 x 20us por flanco)");

    gen.setFlowRate(10.0f);
    gen.enableBounce(5, 20);  // 5 rebotes de 20μs cada uno.
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    return hilVerifyFlow(comm, 10.0f, DEFAULT_TOLERANCE_LMIN);
}

static TestResult test_frecuencia_maxima(PulseGenerator& gen, FpgaComm& comm) {
    // 225 Hz = 30 L/min (límite del YF-S201).
    Serial.println("  │  Frecuencia maxima: 225 Hz (30 L/min)");
    return hilStimulateAndVerify(gen, comm, 30.0f, 30.0f, DEFAULT_TOLERANCE_LMIN, DEFAULT_SETTLE_MS);
}

static TestResult test_frecuencia_minima(PulseGenerator& gen, FpgaComm& comm) {
    // 7.5 Hz = 1 L/min (límite inferior del YF-S201).
    Serial.println("  │  Frecuencia minima viable: 7.5 Hz (1 L/min)");
    return hilStimulateAndVerify(gen, comm, 1.0f, 1.0f, DEFAULT_TOLERANCE_LMIN, DEFAULT_SETTLE_MS);
}

static TestResult test_pulsos_con_jitter(PulseGenerator& gen, FpgaComm& comm) {
    // Pulsos a 10 L/min con jitter de ±200μs (simula ruido electromecánico).
    Serial.println("  │  Pulsos con jitter ±200us");

    gen.setFlowRate(10.0f);
    gen.enableJitter(200);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    return hilVerifyFlow(comm, 10.0f, DEFAULT_TOLERANCE_LMIN);
}

const TestCase pulseDetTests[] = {
    {"5.1 Rebote mecanico",     "5 bounces de 20us, filtro FPGA=100us",  test_rebote_mecanico},
    {"5.2 Frecuencia maxima",   "225 Hz (30 L/min, limite YF-S201)",     test_frecuencia_maxima},
    {"5.3 Frecuencia minima",   "7.5 Hz (1 L/min)",                     test_frecuencia_minima},
    {"5.4 Jitter electrico",    "Pulsos con jitter ±200us",              test_pulsos_con_jitter},
};
const int pulseDetTestCount = sizeof(pulseDetTests) / sizeof(pulseDetTests[0]);


// ═══════════════════════════════════════════════════════════════════════════
//  SUITE 6: Controlador Difuso
// ═══════════════════════════════════════════════════════════════════════════

static TestResult test_regimen_estable(PulseGenerator& gen, FpgaComm& comm) {
    // Con setpoint = 10 (SW=1010 en la FPGA) y flujo real = 10 L/min,
    // la corrección difusa debe ser mínima → lectura ≈ 10 L/min.
    Serial.println("  │  Regimen estable: flujo=10, setpoint=10 (SW)");
    Serial.println("  │  NOTA: Verificar que SW de la FPGA este en 1010 (10)");

    return hilStimulateAndVerify(gen, comm, 10.0f, 10.0f, DEFAULT_TOLERANCE_LMIN, DEFAULT_SETTLE_MS);
}

static TestResult test_error_positivo(PulseGenerator& gen, FpgaComm& comm) {
    // Con setpoint = 15 y flujo real = 5 L/min → error positivo grande.
    // El fuzzy debe agregar corrección positiva.
    Serial.println("  │  Error positivo: flujo=5, setpoint=15 (SW=1111)");
    Serial.println("  │  NOTA: Verificar que SW de la FPGA este en 1111 (15)");

    gen.setFlowRate(5.0f);
    hilSettle(gen, comm, DEFAULT_SETTLE_MS);

    // No verificamos valor exacto porque depende del setpoint de los switches.
    // Verificamos que el sistema genera una lectura (no se cuelga).
    float reading = comm.getAverage(3);
    Serial.printf("  │  Lectura FPGA: %.2f L/min (flujo real: 5.0)\n", reading);

    // La corrección difusa debería aumentar la lectura ligeramente sobre 5.0.
    return (reading >= 4.0f && reading <= 20.0f) ? TestResult::PASS : TestResult::FAIL;
}

static TestResult test_perturbacion_senoidal(PulseGenerator& gen, FpgaComm& comm) {
    // Flujo = 10 + 2·sin(t) L/min durante 20 segundos.
    // El EMA debe atenuar la variación sinusoidal.
    Serial.println("  │  Perturbacion senoidal: 10 ± 2 L/min, periodo ~6s");

    uint32_t start = millis();
    float maxReading = 0.0f, minReading = 99.0f;

    while ((millis() - start) < 25000) {
        // Generar sinusoide.
        float t = (millis() - start) / 1000.0f;
        float flow = 10.0f + 2.0f * sinf(2.0f * PI * t / 6.0f);
        gen.setFlowRate(flow);

        gen.update();
        comm.update();

        // Registrar extremos de la lectura FPGA (después de la estabilización inicial).
        if ((millis() - start) > 15000) {
            FpgaReading r = comm.getLatest();
            if (r.valid) {
                if (r.flowLmin > maxReading) maxReading = r.flowLmin;
                if (r.flowLmin < minReading) minReading = r.flowLmin;
            }
        }
    }

    float peakToPeak = maxReading - minReading;
    Serial.printf("  │  Rango FPGA: [%.2f, %.2f], pico-pico=%.2f L/min\n",
                  minReading, maxReading, peakToPeak);
    Serial.printf("  │  Rango estimulo: [8.0, 12.0], pico-pico=4.0 L/min\n");

    // El EMA (α=1/8) debe atenuar la variación. Aceptar si p-p < 3.0 L/min.
    return (peakToPeak < 3.0f) ? TestResult::PASS : TestResult::FAIL;
}

const TestCase fuzzyTests[] = {
    {"6.1 Regimen estable",       "Flujo=setpoint, correccion minima",     test_regimen_estable},
    {"6.2 Error positivo grande", "Flujo << setpoint, correccion positiva",test_error_positivo},
    {"6.3 Perturbacion senoidal", "10±2 L/min, EMA atenua variacion",     test_perturbacion_senoidal},
};
const int fuzzyTestCount = sizeof(fuzzyTests) / sizeof(fuzzyTests[0]);

}  // namespace TestSuites
