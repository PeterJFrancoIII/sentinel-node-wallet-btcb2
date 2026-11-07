import Foundation

/// Read-only USD valuation. This code NEVER reads or sends wallet addresses,
/// balances, transaction IDs, exchange credentials, or user account data.
public struct BTCB2USDPriceSnapshot: Sendable {
    public let usdPerBTCB2: Double
    public let sourceSummary: String
    public let observedAt: Date
    public let isCrossVenue: Bool
    public let priceIsIndicative: Bool

    public var isStale: Bool { Date().timeIntervalSince(observedAt) > 600 }
}

public struct BTCB2VenueQuote: Sendable {
    public let source: String
    public let usdPerBTCB2: Double
    public let quoteVolumeUSD: Double
}

public enum BTCB2PriceError: Error, LocalizedError, Sendable {
    case unavailable
    case conflictingMarkets

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "No sufficiently liquid, current BTCB2/USDC or BTCB2/USDT public-market quote is available."
        case .conflictingMarkets:
            return "NonKYC and NeoxEX market prices disagree too much to show a reliable blended USD estimate."
        }
    }
}

/// Two external market venues, no API keys, no trading endpoints, no prices for
/// unrelated SHA256d Bitcoin. Poll only while the Wallet tab is visible.
/// USDT/USDC are USD proxies, not guarantees of a $1 conversion.
public actor BTCB2USDPriceOracle {
    private let session: URLSession
    private var cached: BTCB2USDPriceSnapshot?

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 7
        config.timeoutIntervalForResource = 9
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    private func read(_ text: String) async -> Data? {
        guard let url = URL(string: text), url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200, !data.isEmpty, data.count < 100_000
            else { return nil }
            return data
        } catch {
            return nil
        }
    }

    public func latest() async throws -> BTCB2USDPriceSnapshot {
        if let cached, Date().timeIntervalSince(cached.observedAt) < 300 { return cached }

        async let a = read("https://api.nonkyc.io/api/v2/ticker/BTCB2_USDT")
        async let b = read("https://neoxa.exchange/api/exchange/ticker/BTCB2_USDC")
        async let c = read("https://neoxa.exchange/api/exchange/ticker/BTCB2_USDT")
        async let d = read("https://neoxa.exchange/api/prices")
        let (nonData, usdcData, usdtData, fxData) = await (a, b, c, d)
        let usdtUSD = Self.stablecoinUSD(from: fxData, symbol: "USDT") ?? 1
        let usdcUSD = Self.stablecoinUSD(from: fxData, symbol: "USDC") ?? 1

        // A same-venue USDT pair is fallback, NOT an additional independent vote.
        let nonKYC = nonData.flatMap { Self.nonKYCQuote($0, usdtUSD: usdtUSD) }
        let neoxEX = usdcData.flatMap { Self.neoxEXQuote($0, pair: "BTCB2_USDC", stableUSD: usdcUSD) }
            ?? usdtData.flatMap { Self.neoxEXQuote($0, pair: "BTCB2_USDT", stableUSD: usdtUSD) }

        let sources = [nonKYC, neoxEX].compactMap { $0 }
        guard !sources.isEmpty else { throw BTCB2PriceError.unavailable }

        let estimate: Double
        if let nonKYC, let neoxEX {
            let minValue = min(nonKYC.usdPerBTCB2, neoxEX.usdPerBTCB2)
            let maxValue = max(nonKYC.usdPerBTCB2, neoxEX.usdPerBTCB2)
            guard minValue > 0, maxValue / minValue <= 1.12 else {
                throw BTCB2PriceError.conflictingMarkets
            }
            // Equal venue weighting avoids treating two NeoxEX pairs as two exchanges.
            estimate = (nonKYC.usdPerBTCB2 + neoxEX.usdPerBTCB2) / 2
        } else {
            estimate = sources[0].usdPerBTCB2
        }

        let snapshot = BTCB2USDPriceSnapshot(
            usdPerBTCB2: estimate,
            sourceSummary: sources.map(\.source).joined(separator: " + "),
            observedAt: Date(),
            isCrossVenue: sources.count == 2,
            priceIsIndicative: true
        )
        cached = snapshot
        return snapshot
    }

    private static func object(_ data: Data?) -> [String: Any]? {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any] else { return nil }
        return dict
    }

    private static func numeric(_ value: Any?) -> Double? {
        let number: Double?
        switch value {
        case let value as NSNumber: number = value.doubleValue
        case let value as String: number = Double(value)
        default: number = nil
        }
        guard let number, number.isFinite, number > 0 else { return nil }
        return number
    }

    public static func stablecoinUSD(from data: Data?, symbol: String) -> Double? {
        guard symbol == "USDC" || symbol == "USDT",
              let values = object(data)?["prices"] as? [String: Any],
              let fx = numeric(values[symbol]), fx >= 0.95, fx <= 1.05 else { return nil }
        return fx
    }

    private static func vettedMid(bid: Double?, ask: Double?, volume: Double?) -> Double? {
        guard let bid, let ask, let volume,
              ask >= bid, bid > 0, volume >= 100,
              (ask - bid) / ((bid + ask) / 2) <= 0.10 else { return nil }
        return (bid + ask) / 2
    }

    /// NonKYC's ticker does not include a last-trade timestamp. A new HTTP
    /// retrieval is NOT proof of a new trade; use live bid/ask, 24h volume and
    /// clear 'indicative' attribution.
    public static func nonKYCQuote(_ data: Data, usdtUSD: Double = 1) -> BTCB2VenueQuote? {
        guard let json = object(data),
              json["ticker_id"] as? String == "BTCB2_USDT",
              json["base_currency"] as? String == "BTCB2",
              json["target_currency"] as? String == "USDT",
              usdtUSD >= 0.95, usdtUSD <= 1.05,
              let mid = vettedMid(bid: numeric(json["bid"]),
                                  ask: numeric(json["ask"]),
                                  volume: numeric(json["usd_volume_est"]) ?? numeric(json["target_volume"]))
        else { return nil }
        return BTCB2VenueQuote(source: "NonKYC BTCB2/USDT", usdPerBTCB2: mid * usdtUSD,
                              quoteVolumeUSD: (numeric(json["usd_volume_est"]) ?? 0) * usdtUSD)
    }

    public static func neoxEXQuote(_ data: Data, pair: String, stableUSD: Double = 1,
                                   now: Date = Date()) -> BTCB2VenueQuote? {
        guard pair == "BTCB2_USDC" || pair == "BTCB2_USDT",
              stableUSD >= 0.95, stableUSD <= 1.05,
              let json = object(data),
              json["success"] as? Bool == true,
              json["pair"] as? String == pair,
              let ticker = json["ticker"] as? [String: Any],
              let millis = numeric(ticker["computedAt"]),
              abs(now.timeIntervalSince1970 - millis / 1000) < 900,
              let mid = vettedMid(bid: numeric(ticker["bestBid"]),
                                  ask: numeric(ticker["bestAsk"]),
                                  volume: numeric(ticker["quoteVolume24h"]))
        else { return nil }
        return BTCB2VenueQuote(source: "NeoxEX " + pair.replacingOccurrences(of: "_", with: "/"),
                              usdPerBTCB2: mid * stableUSD,
                              quoteVolumeUSD: (numeric(ticker["quoteVolume24h"]) ?? 0) * stableUSD)
    }
}
