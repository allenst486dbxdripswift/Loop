//
//  PacketParser.swift
//  Loop
//
//  Thin wrapper over the verified CareSens Air packet parsing in `CareSensAirProtocol`.
//  Kept as a named entry point; the real framing/decoding lives in CareSensAirProtocol.
//

import Foundation

enum PacketParser {
    /// Parses a `0xC5 0x01` glucose report packet, returning the current glucose (mg/dL).
    static func currentGlucose(from data: Data, valueCount: Int = 1) -> Int? {
        CareSensAirProtocol.parseGlucosePacket(data, valueCount: valueCount)?.currentGlucose
    }

    /// Parses a `0xC4 0x01` packet, returning the number of stored records.
    static func recordCount(from data: Data) -> Int? {
        CareSensAirProtocol.parseRecordCount(data)
    }
}
