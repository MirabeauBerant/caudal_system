//=============================================================================
// test_runner.cpp — Implementación del Motor de Ejecución de Pruebas
//=============================================================================

#include "test_runner.h"

TestRunner::TestRunner(PulseGenerator& gen, FpgaComm& comm)
    : m_gen(gen), m_comm(comm) {}

TestResult TestRunner::runTest(const TestCase& tc) {
    Serial.printf("\n  ┌─ %s\n", tc.name);
    Serial.printf("  │  %s\n", tc.description);

    // Limpiar estado previo.
    m_gen.stop();
    m_gen.clearAllFaults();
    m_comm.clearHistory();
    delay(200);

    // Ejecutar la prueba con cronómetro.
    uint32_t start = millis();
    TestResult result = tc.runFunc(m_gen, m_comm);
    uint32_t duration = millis() - start;

    // Limpiar al finalizar.
    m_gen.stop();
    m_gen.clearAllFaults();

    printTestResult(tc.name, result, duration);
    return result;
}

TestSuiteResult TestRunner::runSuite(const char* suiteName, const TestCase* tests, int count) {
    printHeader(suiteName);

    TestSuiteResult result = {count, 0, 0, 0, 0, 0};
    uint32_t suiteStart = millis();

    for (int i = 0; i < count; i++) {
        TestResult tr = runTest(tests[i]);
        switch (tr) {
            case TestResult::PASS:    result.passed++;   break;
            case TestResult::FAIL:    result.failed++;   break;
            case TestResult::SKIP:    result.skipped++;  break;
            case TestResult::TIMEOUT: result.timedOut++; break;
        }
    }

    result.totalTimeMs = millis() - suiteStart;
    printSummary(result);
    return result;
}

void TestRunner::printSummary(const TestSuiteResult& result) {
    Serial.println("\n  ╔════════════════════════════════════════╗");
    Serial.println("  ║           RESUMEN DE SUITE             ║");
    Serial.println("  ╠════════════════════════════════════════╣");
    Serial.printf( "  ║  Total:    %3d                         ║\n", result.total);
    Serial.printf( "  ║  PASS:     %3d  ✓                      ║\n", result.passed);
    Serial.printf( "  ║  FAIL:     %3d  ✗                      ║\n", result.failed);
    Serial.printf( "  ║  SKIP:     %3d  ⊘                      ║\n", result.skipped);
    Serial.printf( "  ║  TIMEOUT:  %3d  ⏱                      ║\n", result.timedOut);
    Serial.printf( "  ║  Tiempo:   %u ms                  ║\n", (unsigned)result.totalTimeMs);
    Serial.println("  ╚════════════════════════════════════════╝");

    if (result.failed == 0 && result.timedOut == 0) {
        Serial.println("  >>> SUITE COMPLETA: TODOS PASARON <<<");
    } else {
        Serial.printf("  >>> SUITE COMPLETA: %d FALLAS <<<\n", result.failed + result.timedOut);
    }
}

void TestRunner::printHeader(const char* suiteName) {
    Serial.println("\n╔══════════════════════════════════════════════════════════╗");
    Serial.printf( "║  SUITE: %-48s ║\n", suiteName);
    Serial.println("╚══════════════════════════════════════════════════════════╝");
}

void TestRunner::printTestResult(const char* name, TestResult result, uint32_t durationMs) {
    const char* tag = resultToString(result);
    Serial.printf("  └─ [%s] %s  (%u ms)\n", tag, name, (unsigned)durationMs);
}

const char* TestRunner::resultToString(TestResult r) {
    switch (r) {
        case TestResult::PASS:    return "PASS";
        case TestResult::FAIL:    return "FAIL";
        case TestResult::SKIP:    return "SKIP";
        case TestResult::TIMEOUT: return "TOUT";
        default:                  return "????";
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Funciones auxiliares para pruebas
// ═══════════════════════════════════════════════════════════════════════════

void hilSettle(PulseGenerator& gen, FpgaComm& comm, uint32_t settleMs) {
    Serial.printf("  │  Esperando estabilizacion (%u ms)...", (unsigned)settleMs);
    uint32_t start = millis();
    while ((millis() - start) < settleMs) {
        gen.update();
        comm.update();

        // Imprimir progreso cada 2 segundos.
        static uint32_t lastPrint = 0;
        if ((millis() - lastPrint) > 2000) {
            lastPrint = millis();
            FpgaReading r = comm.getLatest();
            if (r.valid) {
                Serial.printf("\n  │    [%lus] FPGA: %.2f L/min",
                              (millis() - start) / 1000, r.flowLmin);
            }
        }
    }
    Serial.println("\n  │  Estabilizacion completa.");
}

TestResult hilVerifyFlow(FpgaComm& comm, float expectedLmin, float toleranceLmin) {
    // Usar promedio de las últimas 3 lecturas para reducir ruido residual.
    float avg = comm.getAverage(3);
    float diff = fabsf(avg - expectedLmin);
    float stddev = comm.getStdDev(3);

    Serial.printf("  │  Verificacion: esperado=%.2f, leido=%.2f, |error|=%.2f, tol=%.2f, stddev=%.3f\n",
                  expectedLmin, avg, diff, toleranceLmin, stddev);

    if (diff <= toleranceLmin) {
        return TestResult::PASS;
    } else {
        Serial.printf("  │  *** FALLO: error %.2f excede tolerancia %.2f ***\n", diff, toleranceLmin);
        return TestResult::FAIL;
    }
}

TestResult hilStimulateAndVerify(PulseGenerator& gen, FpgaComm& comm,
                                  float stimulusLmin, float expectedLmin,
                                  float toleranceLmin, uint32_t settleMs) {
    Serial.printf("  │  Estimulo: %.2f L/min → Esperado: %.2f L/min\n", stimulusLmin, expectedLmin);

    // Aplicar estímulo.
    if (stimulusLmin > 0.0f) {
        gen.setFlowRate(stimulusLmin);
    } else {
        gen.stop();
    }

    // Esperar estabilización del pipeline.
    hilSettle(gen, comm, settleMs);

    // Verificar resultado.
    return hilVerifyFlow(comm, expectedLmin, toleranceLmin);
}
