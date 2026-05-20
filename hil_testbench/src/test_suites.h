//=============================================================================
// test_suites.h — Declaración de las 6 Suites de Prueba HIL
//=============================================================================

#pragma once
#include "test_runner.h"

namespace TestSuites {

// Suite 1: Topes y Zona Muerta
extern const TestCase limitsTests[];
extern const int      limitsTestCount;

// Suite 2: Linealidad del Pipeline
extern const TestCase linearityTests[];
extern const int      linearityTestCount;

// Suite 3: Respuesta Dinámica
extern const TestCase dynamicsTests[];
extern const int      dynamicsTestCount;

// Suite 4: Detección de Anomalías
extern const TestCase anomalyTests[];
extern const int      anomalyTestCount;

// Suite 5: Robustez del Pulse Detector
extern const TestCase pulseDetTests[];
extern const int      pulseDetTestCount;

// Suite 6: Controlador Difuso
extern const TestCase fuzzyTests[];
extern const int      fuzzyTestCount;

}  // namespace TestSuites
