//=============================================================================
// main.cpp — Punto de entrada del Banco de Pruebas HIL
//
// Proyecto : Caudalímetro Difuso Embebido en FPGA
// Módulo   : Banco HIL (ESP32 XX5R69)
//
// Interfaz por monitor serial (115200 baud):
//   - Selección de suites de prueba automatizadas (1-6, a=todas)
//   - Modo manual para depuración interactiva (f<valor>, s, r, m)
//
// Conexiones:
//   GPIO 25 → FPGA PIN_119 (i_sensor)    Pulsos del sensor simulado
//   GPIO 16 ← FPGA PIN_118 (o_uart_tx)   Telemetría Q8.8 de la FPGA
//   GPIO 26 ← FPGA (status OK)           Diagnóstico (opcional)
//   GPIO 27 ← FPGA (status WARN)         Diagnóstico (opcional)
//   GPIO 14 ← FPGA (status ALERT)        Diagnóstico (opcional)
//=============================================================================

#include <Arduino.h>
#include "config.h"
#include "pulse_gen.h"
#include "fpga_comm.h"
#include "test_runner.h"
#include "test_suites.h"

// ── Instancias globales ──
PulseGenerator pulseGen;
FpgaComm       fpgaComm;
TestRunner     runner(pulseGen, fpgaComm);

// ── Estado del modo manual ──
bool manualMonitor = false;
uint32_t lastMonitorPrint = 0;

// ═══════════════════════════════════════════════════════════════════════════
//  Menú principal
// ═══════════════════════════════════════════════════════════════════════════

void printMenu() {
    Serial.println();
    Serial.println("======================================================");
    Serial.println("   Banco de Pruebas HIL - Caudalimetro Difuso FPGA");
    Serial.println("   ESP32 XX5R69 | PlatformIO");
    Serial.println("======================================================");
    Serial.println();
    Serial.println("  SUITES DE PRUEBA AUTOMATIZADAS:");
    Serial.println("    1 - Topes y Zona Muerta (Deadband/Clamping)");
    Serial.println("    2 - Linealidad del Pipeline");
    Serial.println("    3 - Respuesta Dinamica (Escalones)");
    Serial.println("    4 - Deteccion de Anomalias");
    Serial.println("    5 - Robustez del Pulse Detector");
    Serial.println("    6 - Controlador Difuso");
    Serial.println("    a - Ejecutar TODAS las suites");
    Serial.println();
    Serial.println("  MODO MANUAL:");
    Serial.println("    f<valor>  - Fijar caudal (ej: f10.5)");
    Serial.println("    s         - Detener pulsos");
    Serial.println("    r         - Leer ultima lectura FPGA");
    Serial.println("    w         - Monitor continuo (toggle)");
    Serial.println("    d         - Leer pines de diagnostico");
    Serial.println("    m         - Mostrar este menu");
    Serial.println();
    Serial.println("------------------------------------------------------");
}

// ═══════════════════════════════════════════════════════════════════════════
//  Ejecución de suites
// ═══════════════════════════════════════════════════════════════════════════

void runAllSuites() {
    Serial.println("\n*** EJECUTANDO TODAS LAS SUITES ***\n");

    TestSuiteResult total = {0, 0, 0, 0, 0, 0};
    uint32_t globalStart = millis();

    auto accumulate = [&total](const TestSuiteResult& r) {
        total.total    += r.total;
        total.passed   += r.passed;
        total.failed   += r.failed;
        total.skipped  += r.skipped;
        total.timedOut += r.timedOut;
    };

    accumulate(runner.runSuite("1. Topes y Zona Muerta",
               TestSuites::limitsTests, TestSuites::limitsTestCount));

    accumulate(runner.runSuite("2. Linealidad del Pipeline",
               TestSuites::linearityTests, TestSuites::linearityTestCount));

    accumulate(runner.runSuite("3. Respuesta Dinamica",
               TestSuites::dynamicsTests, TestSuites::dynamicsTestCount));

    accumulate(runner.runSuite("4. Deteccion de Anomalias",
               TestSuites::anomalyTests, TestSuites::anomalyTestCount));

    accumulate(runner.runSuite("5. Robustez del Pulse Detector",
               TestSuites::pulseDetTests, TestSuites::pulseDetTestCount));

    accumulate(runner.runSuite("6. Controlador Difuso",
               TestSuites::fuzzyTests, TestSuites::fuzzyTestCount));

    total.totalTimeMs = millis() - globalStart;

    Serial.println("\n======================================================");
    Serial.println("            REPORTE FINAL — TODAS LAS SUITES");
    Serial.println("======================================================");
    runner.printSummary(total);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Procesamiento de comandos serial
// ═══════════════════════════════════════════════════════════════════════════

void handleSerial() {
    if (!Serial.available()) return;

    String input = Serial.readStringUntil('\n');
    input.trim();
    if (input.length() == 0) return;

    char cmd = input.charAt(0);

    switch (cmd) {
        case '1':
            runner.runSuite("1. Topes y Zona Muerta",
                            TestSuites::limitsTests, TestSuites::limitsTestCount);
            break;
        case '2':
            runner.runSuite("2. Linealidad del Pipeline",
                            TestSuites::linearityTests, TestSuites::linearityTestCount);
            break;
        case '3':
            runner.runSuite("3. Respuesta Dinamica",
                            TestSuites::dynamicsTests, TestSuites::dynamicsTestCount);
            break;
        case '4':
            runner.runSuite("4. Deteccion de Anomalias",
                            TestSuites::anomalyTests, TestSuites::anomalyTestCount);
            break;
        case '5':
            runner.runSuite("5. Robustez del Pulse Detector",
                            TestSuites::pulseDetTests, TestSuites::pulseDetTestCount);
            break;
        case '6':
            runner.runSuite("6. Controlador Difuso",
                            TestSuites::fuzzyTests, TestSuites::fuzzyTestCount);
            break;
        case 'a':
        case 'A':
            runAllSuites();
            break;
        case 'f':
        case 'F': {
            // Comando manual: f<valor>, ej: f10.5
            float flow = input.substring(1).toFloat();
            if (flow < 0.0f) flow = 0.0f;
            pulseGen.setFlowRate(flow);
            Serial.printf(">> Caudal manual: %.2f L/min (freq=%.1f Hz)\n",
                          flow, flow * PULSES_PER_LITER_MIN);
            break;
        }
        case 's':
        case 'S':
            pulseGen.stop();
            Serial.println(">> Pulsos detenidos.");
            break;
        case 'r':
        case 'R': {
            FpgaReading r = fpgaComm.getLatest();
            if (r.valid) {
                Serial.printf(">> FPGA: %.2f L/min (raw=0x%04X) | Simulado: %.2f L/min\n",
                              r.flowLmin, r.raw, pulseGen.getFlowRate());
            } else {
                Serial.println(">> Sin lectura FPGA disponible.");
            }
            break;
        }
        case 'w':
        case 'W':
            manualMonitor = !manualMonitor;
            Serial.printf(">> Monitor continuo: %s\n", manualMonitor ? "ACTIVADO" : "DESACTIVADO");
            break;
        case 'd':
        case 'D': {
            int ok    = digitalRead(PIN_STATUS_OK);
            int warn  = digitalRead(PIN_STATUS_WARN);
            int alert = digitalRead(PIN_STATUS_ALERT);
            Serial.printf(">> Diagnostico FPGA — OK:%d  WARN:%d  ALERT:%d\n", ok, warn, alert);
            break;
        }
        case 'm':
        case 'M':
            printMenu();
            break;
        default:
            Serial.printf(">> Comando desconocido: '%c'. Presiona 'm' para menu.\n", cmd);
            break;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Setup y Loop
// ═══════════════════════════════════════════════════════════════════════════

void setup() {
    Serial.begin(SERIAL_BAUD_RATE);
    delay(1000);  // Esperar a que el monitor serial se conecte.

    // Inicializar módulos.
    pulseGen.begin(PIN_PULSE_OUT);
    fpgaComm.begin(Serial2, PIN_FPGA_UART_RX, PIN_FPGA_UART_TX, FPGA_BAUD_RATE);

    // Configurar pines de diagnóstico (entradas con pull-down).
    pinMode(PIN_STATUS_OK,    INPUT_PULLDOWN);
    pinMode(PIN_STATUS_WARN,  INPUT_PULLDOWN);
    pinMode(PIN_STATUS_ALERT, INPUT_PULLDOWN);

    printMenu();
}

void loop() {
    // Actualizar generador de pulsos y comunicación FPGA.
    pulseGen.update();
    fpgaComm.update();

    // Procesar comandos del usuario.
    handleSerial();

    // Monitor continuo (si está activado).
    if (manualMonitor && (millis() - lastMonitorPrint > 1000)) {
        lastMonitorPrint = millis();
        FpgaReading r = fpgaComm.getLatest();
        if (r.valid) {
            Serial.printf("[MON] FPGA=%.2f L/min | SIM=%.2f L/min | freq=%.1f Hz\n",
                          r.flowLmin, pulseGen.getFlowRate(), pulseGen.getFrequency());
        }
    }
}
