import Foundation

/// BIP-173 (Bech32) and BIP-350 (Bech32m) address encoder, decoder, and validator for Bitcoin MainNet (hrp: "bc").
public enum Bech32: Sendable {
    private static let charset: [Character] = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    public enum Encoding: Sendable {
        case bech32
        case bech32m

        var constant: UInt32 {
            switch self {
            case .bech32: return 1
            case .bech32m: return 0x2bc830a3
            }
        }
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var ch: UInt32 = 1
        for v in values {
            let b = ch >> 25
            ch = ((ch & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 {
                if ((b >> i) & 1) != 0 {
                    ch ^= generator[i]
                }
            }
        }
        return ch
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var ret: [UInt8] = []
        for c in hrp.utf8 {
            ret.append(UInt8(c >> 5))
        }
        ret.append(0)
        for c in hrp.utf8 {
            ret.append(UInt8(c & 31))
        }
        return ret
    }

    private static func verifyChecksum(hrp: String, data: [UInt8]) -> Encoding? {
        let values = hrpExpand(hrp) + data
        let poly = polymod(values)
        if poly == Encoding.bech32.constant {
            return .bech32
        } else if poly == Encoding.bech32m.constant {
            return .bech32m
        }
        return nil
    }

    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var ret: [UInt8] = []
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1

        for value in data {
            let v = Int(value)
            if v < 0 || (v >> fromBits) != 0 {
                return nil
            }
            acc = ((acc << fromBits) | v) & maxAcc
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                ret.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 {
                ret.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        return ret
    }

    /// Validates a Bitcoin MainNet native SegWit address according to BIP-173 and BIP-350.
    /// Strictly checks HRP ("bc"), valid 5-bit character encoding, 30-bit polymod checksum,
    /// witness version constraints (v0 uses Bech32; v1-v16 use Bech32m), and witness program length (2-40 bytes).
    public static func validateMainnetAddress(_ address: String) -> Bool {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)

        // Lowercase or uppercase allowed, but NEVER mixed case
        let isLower = clean == clean.lowercased()
        let isUpper = clean == clean.uppercased()
        guard isLower || isUpper else { return false }

        let lower = clean.lowercased()

        // Bitcoin MainNet strictly uses HRP 'bc' (never 'tb', 'bcrt', etc.)
        guard lower.hasPrefix("bc1") else { return false }
        guard lower.count >= 14 && lower.count <= 74 else { return false }

        let hrp = "bc"
        let dataChars = Array(lower.dropFirst(3))
        guard dataChars.count >= 6 else { return false } // 6-character checksum required

        // Map characters to 5-bit values
        var data5Bit: [UInt8] = []
        for c in dataChars {
            guard let idx = charset.firstIndex(of: c) else { return false }
            data5Bit.append(UInt8(idx))
        }

        // Verify checksum
        guard let encoding = verifyChecksum(hrp: hrp, data: data5Bit) else {
            return false
        }

        // Payload data (excluding 6-byte checksum)
        let payload5Bit = Array(data5Bit.dropLast(6))
        guard let witnessVersion = payload5Bit.first else { return false }
        guard witnessVersion <= 16 else { return false }

        let program5Bit = Array(payload5Bit.dropFirst())
        guard let program = convertBits(data: program5Bit, fromBits: 5, toBits: 8, pad: false) else {
            return false
        }

        guard program.count >= 2 && program.count <= 40 else { return false }

        // BIP-173 vs BIP-350 rules:
        // Version 0 MUST use Bech32 and must be exactly 20 bytes (P2WPKH) or 32 bytes (P2WSH)
        if witnessVersion == 0 {
            guard encoding == .bech32 else { return false }
            guard program.count == 20 || program.count == 32 else { return false }
        } else {
            // Version 1..16 MUST use Bech32m (e.g. Taproot v1 is 32 bytes)
            guard encoding == .bech32m else { return false }
        }

        return true
    }
}
