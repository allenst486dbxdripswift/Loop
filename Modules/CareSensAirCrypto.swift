import Foundation
import CommonCrypto

/// AES‑128 CBC (PKCS7 Padding) encryption/decryption for CareSens Air CGM.
struct CareSensAirCrypto {
    private static let keyString = "tq1Tg265o4UFD8tfPvNqUCiYyCxkhdZV"

    /// Generates 16-byte IV using the serial number.
    /// Format: Suffix6 + Suffix6 + Suffix4 (total 16 bytes).
    static func generateIV(serialNumber: String) -> Data {
        let suffix6 = String(serialNumber.suffix(6))
        let suffix4 = String(serialNumber.suffix(4))
        let ivString = suffix6 + suffix6 + suffix4
        return Data(ivString.utf8)
    }

    static func encrypt(_ plainData: Data, serialNumber: String) -> Data? {
        return crypt(operation: CCOperation(kCCEncrypt), data: plainData, serialNumber: serialNumber)
    }

    static func decrypt(_ cipherData: Data, serialNumber: String) -> Data? {
        return crypt(operation: CCOperation(kCCDecrypt), data: cipherData, serialNumber: serialNumber)
    }

    private static func crypt(operation: CCOperation, data: Data, serialNumber: String) -> Data? {
        // Use first 16 bytes for AES-128
        let keyData = Data(keyString.utf8).prefix(16)
        let ivData  = generateIV(serialNumber: serialNumber)

        let outputBufferSize = data.count + kCCBlockSizeAES128
        var outputBuffer = [UInt8](repeating: 0, count: outputBufferSize)
        var outputLength: size_t = 0

        let status: CCCryptorStatus = keyData.withUnsafeBytes { keyPtr in
            ivData.withUnsafeBytes { ivPtr in
                data.withUnsafeBytes { dataPtr in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress,
                        keyData.count,
                        ivPtr.baseAddress,
                        dataPtr.baseAddress,
                        data.count,
                        &outputBuffer,
                        outputBufferSize,
                        &outputLength
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return Data(outputBuffer.prefix(outputLength))
    }
}
