import Foundation

/// ADC → mg/dL conversion (constants extracted from libCALCULATION.so)
struct GlucoseConverter {
    private static let factor = 0.025   // voltage per ADC step
    private static let scale  = 1.2     // sensor‑specific scaling

    static func convert(adc: Double) -> Double {
        return adc * factor * scale
    }
}
