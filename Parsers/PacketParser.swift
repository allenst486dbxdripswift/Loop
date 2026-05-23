import Foundation

/// Parses raw data packets from the CGM (header 0xAA55, length 20 bytes)
struct PacketParser {
    static func parse(_ data: Data) -> Double? {
        guard data.count >= 20 else { return nil }
        let header = data.prefix(2)
        guard header[0] == 0xAA && header[1] == 0x55 else { return nil }
        let adcBytes = data.subdata(in: 4..<8)
        let adc = adcBytes.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        return GlucoseConverter.convert(adc: Double(adc))
    }
}
