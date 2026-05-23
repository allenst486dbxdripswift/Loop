import Foundation
import CryptoKit
import CommonCrypto

/// AES‑256 CTR (no‑padding) decryption for CareSens Air CGM.
struct CareSensAirCrypto {
    private static let keyString = "tq1Tg265o4UFD8tfPvNqUCiYyCxkhdZV"
    private static let keyData = Data(keyString.utf8)
    private static let iv = Data(repeating: 0, count: 16)   // placeholder nonce

    static func decrypt(_ ciphertext: Data) -> Data? {
        var out = Data(count: ciphertext.count)
        var outLen: size_t = 0

        let status = out.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            var cryptor: CCCryptorRef?
            let create = CCCryptorCreateWithMode(
                CCOperation(kCCDecrypt),
                CCMode(kCCModeCTR),
                CCAlgorithm(kCCAlgorithmAES),
                CCPadding(ccNoPadding),
                iv.withUnsafeBytes { $0.baseAddress },
                keyData.withUnsafeBytes { $0.baseAddress },
                keyData.count,
                nil, 0, 0,
                CCModeOptions(kCCModeOptionCTR_LE),
                &cryptor)

            guard create == kCCSuccess, let ctx = cryptor else { return create }

            let upd = CCCryptorUpdate(ctx,
                                      ciphertext.withUnsafeBytes { $0.baseAddress },
                                      ciphertext.count,
                                      outPtr.baseAddress,
                                      out.count,
                                      &outLen)

            CCCryptorRelease(ctx)
            return upd
        }

        guard status == kCCSuccess else { return nil }
        out.removeSubrange(outLen..<out.count)
        return out
    }
}
