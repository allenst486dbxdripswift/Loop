import Foundation
import CryptoKit
import CommonCrypto

/// AES‑128 CBC (PKCS7 Padding) encryption/decryption for CareSens Air CGM.
struct CareSensAirCrypto {
    private static let keyString = "tq1Tg265o4UFD8tfPvNqUCiYyCxkhdZV"
    
    /// Generates 16-byte IV using the serial number.
    /// Format: Suffix6 + Suffix6 + Suffix4.
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
        let keyBytes = Data(keyString.utf8).prefix(16)
        let iv = generateIV(serialNumber: serialNumber)

        var out = Data(count: data.count + kCCBlockSizeAES128)
        var outLen: size_t = 0
        
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                keyBytes.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress,
                            keyBytes.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress,
                            data.count,
                            outPtr.baseAddress,
                            out.count,
                            &outLen
                        )
                    }
                }
            }
        }
        
        guard status == kCCSuccess else { return nil }
        return Data(out.prefix(outLen))
    }
}
