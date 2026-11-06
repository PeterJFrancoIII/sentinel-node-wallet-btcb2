import Foundation

/// Mathematical and consensus helpers for BIP-110 / BTCB2 target, difficulty, and work calculations.
public enum TargetConverter {
    /// Diff1 Target constant (0x1d00ffff): ~2^32 expected hashes
    /// 0x00000000FFFF0000000000000000000000000000000000000000000000000000
    public static let diff1TargetHex: String = "00000000ffff0000000000000000000000000000000000000000000000000000"
    public static let diff1TargetDouble: Double = 0x00000000FFFF0000 * pow(256.0, 24.0)

    /// Decodes Bitcoin compact nBits to canonical 64-hex-digit 256-bit target string.
    public static func targetHexFromBits(_ bits: UInt32) -> String? {
        let exponent = Int(bits >> 24)
        let mantissa = UInt64(bits & 0x007FFFFF)
        let isNegative = (bits & 0x00800000) != 0

        guard !isNegative, mantissa > 0 else {
            return nil
        }

        // Target = mantissa * 256^(exponent - 3)
        // 256 bytes = 32 bytes = 64 hex chars
        var bytes = [UInt8](repeating: 0, count: 32)

        if exponent <= 3 {
            let shift = 8 * (3 - exponent)
            let shiftedMantissa = mantissa >> shift
            guard shiftedMantissa > 0 else { return nil }
            bytes[31] = UInt8(shiftedMantissa & 0xFF)
            bytes[30] = UInt8((shiftedMantissa >> 8) & 0xFF)
            bytes[29] = UInt8((shiftedMantissa >> 16) & 0xFF)
        } else {
            let offset = exponent - 3
            guard offset + 2 < 32 else { return nil } // Exceeds 256 bits

            let m0 = UInt8(mantissa & 0xFF)
            let m1 = UInt8((mantissa >> 8) & 0xFF)
            let m2 = UInt8((mantissa >> 16) & 0xFF)

            // High byte is at index (31 - (offset + 2)) in big-endian byte array
            let baseIndex = 31 - offset
            bytes[baseIndex] = m0
            bytes[baseIndex - 1] = m1
            bytes[baseIndex - 2] = m2
        }

        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Derives standard Bitcoin difficulty (bdiff) from target hex string.
    public static func difficultyFromTarget(targetHex: String) -> Double {
        let cleanHex = targetHex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "")
            .lowercased()
        guard cleanHex.count == 64 else { return 0.0 }

        // Use top 16 hex digits (64 bits) for floating-point ratio with exponent compensation
        // Find first non-zero byte
        let hexChars = Array(cleanHex)
        var firstNonZero = -1
        for i in 0..<hexChars.count {
            if hexChars[i] != "0" {
                firstNonZero = i
                break
            }
        }
        guard firstNonZero >= 0 else { return 0.0 }

        // Take up to 16 hex characters from first non-zero for high precision mantissa
        let endIndex = min(firstNonZero + 16, 64)
        let subStr = String(hexChars[firstNonZero..<endIndex])
        guard let mantissa = UInt64(subStr, radix: 16), mantissa > 0 else { return 0.0 }

        let exponentInBits = (64 - firstNonZero) * 4
        let subStrBits = subStr.count * 4
        let totalShift = Double(exponentInBits - subStrBits)
        let targetValue = Double(mantissa) * pow(2.0, totalShift)

        guard targetValue > 0 else { return 0.0 }
        return diff1TargetDouble / targetValue
    }

    /// Derives expected hashes per block from exact 256-bit target: 2^256 / (target + 1)
    public static func expectedHashesFromTarget(targetHex: String) -> Double {
        let diff = difficultyFromTarget(targetHex: targetHex)
        guard diff > 0 else { return 0.0 }
        // diff * 2^32 is standard expected hashes for difficulty
        return diff * pow(2.0, 32.0)
    }

    /// Nominal hashrate in PetaHashes per second (PH/s) for expected hashes and target block interval (default 600s).
    public static func nominalHashratePH(expectedHashes: Double, targetSeconds: Double = 600.0) -> Double {
        guard expectedHashes > 0, targetSeconds > 0 else { return 0.0 }
        return expectedHashes / targetSeconds / 1e15
    }
}
