//=============================================================================
// test_runner.h — Motor de Ejecución de Pruebas HIL
//
// Proporciona la infraestructura para definir, ejecutar y reportar
// pruebas individuales y suites de prueba con criterios PASS/FAIL.
//=============================================================================

#pragma once
#include <Arduino.h>
#include "pulse_gen.h"
#include "fpga_comm.h"

/// Resultado de una prueba individual.
enum class TestResult {
    PASS,
    FAIL,
    SKIP,
    TIMEOUT
};

/// Definición de un caso de prueba individual.
struct TestCase {
    const char* name;         // Nombre corto (ej: "1.1 Deadband inferior")
    const char* description;  // Descripción detallada del estímulo y verificación
    TestResult (*runFunc)(PulseGenerator& gen, FpgaComm& comm);  // Función de prueba
};

/// Resultado agregado de una suite de pruebas.
struct TestSuiteResult {
    int      total;
    int      passed;
    int      failed;
    int      skipped;
    int      timedOut;
    uint32_t totalTimeMs;
};

class TestRunner {
public:
    TestRunner(PulseGenerator& gen, FpgaComm& comm);

    /// Ejecutar un solo caso de prueba con cronómetro.
    TestResult runTest(const TestCase& tc);

    /// Ejecutar una suite completa de pruebas.
    TestSuiteResult runSuite(const char* suiteName, const TestCase* tests, int count);

    /// Imprimir resumen final de la suite.
    void printSummary(const TestSuiteResult& result);

private:
    PulseGenerator& m_gen;
    FpgaComm&       m_comm;

    void printHeader(const char* suiteName);
    void printTestResult(const char* name, TestResult result, uint32_t durationMs);
    const char* resultToString(TestResult r);
};

// ═══════════════════════════════════════════════════════════════════════════
//  Funciones auxiliares para pruebas
// ═══════════════════════════════════════════════════════════════════════════

/// Esperar estabilización del pipeline FPGA mientras mantiene pulsos activos.
/// Muestra progreso en la consola serial.
void hilSettle(PulseGenerator& gen, FpgaComm& comm, uint32_t settleMs);

/// Verificar que la lectura de la FPGA está dentro de tolerancia.
/// Retorna PASS si |fpga_reading - expectedLmin| <= tolerance.
TestResult hilVerifyFlow(FpgaComm& comm, float expectedLmin, float toleranceLmin);

/// Flujo combinado: establecer estímulo, esperar estabilización, verificar.
TestResult hilStimulateAndVerify(PulseGenerator& gen, FpgaComm& comm,
                                 float stimulusLmin, float expectedLmin,
                                 float toleranceLmin, uint32_t settleMs);
