import Foundation

/// A single exchange quote from a supported trading venue.
public struct ExchangeQuote: Sendable, Equatable, Codable {
    public let exchange: String       // e.g. "Neoxa" or "NonKYC"
    public let pair: String           // e.g. "BTCB2_USDC" or "BTCB2_USDT"
    public let quoteCurrency: String  // e.g. "USDC" or "USDT"
    public let price: Double
    public let timestamp: Date

    public init(exchange: String, pair: String, quoteCurrency: String, price: Double, timestamp: Date = Date()) {
        self.exchange = exchange
        self.pair = pair
        self.quoteCurrency = quoteCurrency
        self.price = price
        self.timestamp = timestamp
    }
}

/// The aggregated price state across Neoxa, NonKYC, or a user-defined manual override.
public struct BTCB2PriceState: Sendable, Equatable, Codable {
    public var effectivePrice: Double
    public var effectiveSource: String
    public var effectiveCurrency: String
    public var highestMarketPrice: Double
    public var highestMarketSource: String
    public var highestMarketCurrency: String
    public var neoxaQuote: ExchangeQuote?
    public var nonKycQuote: ExchangeQuote?
    public var isOverridden: Bool
    public var customPrice: Double?
    public var lastFetched: Date?
    public var isStale: Bool

    public init(
        effectivePrice: Double = 0.0,
        effectiveSource: String = "None",
        effectiveCurrency: String = "USD",
        highestMarketPrice: Double = 0.0,
        highestMarketSource: String = "None",
        highestMarketCurrency: String = "USD",
        neoxaQuote: ExchangeQuote? = nil,
        nonKycQuote: ExchangeQuote? = nil,
        isOverridden: Bool = false,
        customPrice: Double? = nil,
        lastFetched: Date? = nil,
        isStale: Bool = true
    ) {
        self.effectivePrice = effectivePrice
        self.effectiveSource = effectiveSource
        self.effectiveCurrency = effectiveCurrency
        self.highestMarketPrice = highestMarketPrice
        self.highestMarketSource = highestMarketSource
        self.highestMarketCurrency = highestMarketCurrency
        self.neoxaQuote = neoxaQuote
        self.nonKycQuote = nonKycQuote
        self.isOverridden = isOverridden
        self.customPrice = customPrice
        self.lastFetched = lastFetched
        self.isStale = isStale
    }

    /// Formats a satoshi amount into fiat equivalent string.
    public func formatFiat(satoshis: Int64) -> String {
        let btc = Double(satoshis) / 100_000_000.0
        return formatFiat(btc: btc)
    }

    /// Formats a BTCB2 double amount into fiat equivalent string.
    public func formatFiat(btc: Double) -> String {
        guard effectivePrice > 0 else { return "—" }
        let value = btc * effectivePrice
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let numStr = formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
        return "\(numStr) \(effectiveCurrency)"
    }
}

/// Service that queries Neoxa and NonKYC exchange APIs for live BTCB2 pricing,
/// picks whichever is the highest price, tracks price provenance, and supports
/// manual user overrides if APIs are stale or missing.
public actor BTCB2PriceService {
    public static let shared = BTCB2PriceService()

    private var state: BTCB2PriceState = BTCB2PriceState()
    private let session: URLSession

    public static let neoxaEndpoint = URL(string: "https://neoxa.exchange/api/exchange/ticker/BTCB2_USDC")!
    public static let nonKycEndpoint = URL(string: "https://api.nonkyc.io/api/v2/ticker/BTCB2_USDT")!
    public static let staleThresholdSeconds: TimeInterval = 10 * 60 // 10 minutes

    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 8.0
        self.session = session ?? URLSession(configuration: config)
    }

    public func getCurrentState() -> BTCB2PriceState {
        return self.state
    }

    public func setCustomOverride(price: Double) -> BTCB2PriceState {
        guard price > 0 else {
            return clearCustomOverride()
        }
        state.customPrice = price
        state.isOverridden = true
        state.effectivePrice = price
        state.effectiveSource = "Custom Override"
        state.effectiveCurrency = "USD"
        state.isStale = false
        return state
    }

    public func clearCustomOverride() -> BTCB2PriceState {
        state.isOverridden = false
        state.customPrice = nil
        recalculateEffective()
        return state
    }

    /// Fetches live quotes from Neoxa and NonKYC concurrently and returns updated state.
    @discardableResult
    public func refreshPrice() async -> BTCB2PriceState {
        async let neoxaResult = fetchNeoxaQuote()
        async let nonKycResult = fetchNonKycQuote()

        let (neoxa, nonKyc) = await (neoxaResult, nonKycResult)

        if let n = neoxa {
            state.neoxaQuote = n
        }
        if let nk = nonKyc {
            state.nonKycQuote = nk
        }

        let now = Date()
        state.lastFetched = now

        // Determine highest market price
        var highest: ExchangeQuote? = nil
        if let n = state.neoxaQuote, let nk = state.nonKycQuote {
            highest = (n.price >= nk.price) ? n : nk
        } else if let n = state.neoxaQuote {
            highest = n
        } else if let nk = state.nonKycQuote {
            highest = nk
        }

        if let h = highest {
            state.highestMarketPrice = h.price
            state.highestMarketSource = h.exchange
            state.highestMarketCurrency = h.quoteCurrency
            let age = now.timeIntervalSince(h.timestamp)
            state.isStale = (age > Self.staleThresholdSeconds)
        } else {
            state.isStale = true
        }

        recalculateEffective()
        return state
    }

    private func recalculateEffective() {
        if state.isOverridden, let override = state.customPrice, override > 0 {
            state.effectivePrice = override
            state.effectiveSource = "Custom Override"
            state.effectiveCurrency = "USD"
            state.isStale = false
        } else if state.highestMarketPrice > 0 {
            state.effectivePrice = state.highestMarketPrice
            state.effectiveSource = state.highestMarketSource
            state.effectiveCurrency = state.highestMarketCurrency
        } else {
            state.effectivePrice = 0.0
            state.effectiveSource = "None"
            state.effectiveCurrency = "USD"
        }
    }

    // MARK: - API Fetchers

    private func fetchNeoxaQuote() async -> ExchangeQuote? {
        do {
            var request = URLRequest(url: Self.neoxaEndpoint)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            // Structure: {"success":true,"pair":"BTCB2_USDC","ticker":{"lastPrice":286.23,...}}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ticker = json["ticker"] as? [String: Any] else {
                return nil
            }

            var price: Double? = nil
            if let p = ticker["lastPrice"] as? Double {
                price = p
            } else if let pStr = ticker["lastPrice"] as? String, let p = Double(pStr) {
                price = p
            }

            guard let finalPrice = price, finalPrice > 0 else { return nil }
            return ExchangeQuote(
                exchange: "Neoxa",
                pair: "BTCB2_USDC",
                quoteCurrency: "USDC",
                price: finalPrice,
                timestamp: Date()
            )
        } catch {
            return nil
        }
    }

    private func fetchNonKycQuote() async -> ExchangeQuote? {
        do {
            var request = URLRequest(url: Self.nonKycEndpoint)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            // Structure: {"ticker_id":"BTCB2_USDT","last_price":"284.43",...}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var price: Double? = nil
            if let p = json["last_price"] as? Double {
                price = p
            } else if let pStr = json["last_price"] as? String, let p = Double(pStr) {
                price = p
            }

            guard let finalPrice = price, finalPrice > 0 else { return nil }
            return ExchangeQuote(
                exchange: "NonKYC",
                pair: "BTCB2_USDT",
                quoteCurrency: "USDT",
                price: finalPrice,
                timestamp: Date()
            )
        } catch {
            return nil
        }
    }
}
