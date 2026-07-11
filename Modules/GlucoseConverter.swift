//
//  GlucoseConverter.swift
//  Loop
//
//  Helpers for CareSens Air sensor telemetry. The glucose values in the 0xC5 report
//  packet are already in mg/dL, so no ADC→mg/dL conversion is needed. This provides the
//  battery-voltage conversion (formula from the decompiled app) for status display.
//

import Foundation

enum GlucoseConverter {
    /// Converts the raw battery reading (0…4095) from the report packet into volts.
    /// Mirrors the official app: round(((raw/4095)*43000*2 + 0.5)/10000 * 10000)/10000.
    static func batteryVoltage(rawBattery raw: Int) -> Double {
        let v = ((Double(raw) / 4095.0) * 43000.0 * 2.0 + 0.5) / 10000.0
        return (v * 10000.0).rounded() / 10000.0
    }
}
