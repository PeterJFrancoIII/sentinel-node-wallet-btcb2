import Foundation
import Security

/// Generates an encryption passphrase for a Knots descriptor wallet.
/// This is NOT a BIP39 seed phrase and cannot restore wallet descriptors.
public enum WalletPassphraseGenerator {
    public enum GenerationError: Error, LocalizedError {
        case randomUnavailable

        public var errorDescription: String? {
            "Secure passphrase generation failed; wallet creation has not started."
        }
    }

    public static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw GenerationError.randomUnavailable }
        defer { bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
