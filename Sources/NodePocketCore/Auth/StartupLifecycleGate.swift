import Foundation

/// Explicit outcome of evaluating initial autonomous node bootstrap against durable auth state.
public enum StartupBootstrapOutcome: Equatable, Sendable {
    case awaitingAuthResolution
    case requiresInitialEnrollment
    case blockedCorruptedOrMissingRegistry(String)
    case alreadyBootstrappedOrActive
    case startedNode(usernames: [String])
    case nodeStartSkippedOrFailed
}

/// Explicit authorization outcome before any mutating node start/adopt/restart/configuration path.
public struct NodeMutationAuthorization: Equatable, Sendable {
    public let allowed: Bool
    public let durableState: DurableAuthState
    public let reason: String?

    public init(allowed: Bool, durableState: DurableAuthState, reason: String?) {
        self.allowed = allowed
        self.durableState = durableState
        self.reason = reason
    }
}

/// Single-flight coordinator gating autonomous node startup and mutating node settings
/// behind durable, persisted operator enrollment (`auth_registry.json`).
@MainActor
public final class StartupLifecycleGate {
    public private(set) var durableAuthState: DurableAuthState = .unknown
    public private(set) var hasCompletedAutoBootstrap: Bool = false
    private var isBootstrapInFlight: Bool = false

    public init() {}

    @discardableResult
    public func refreshDurableState(using authCoordinator: WalletAuthCoordinator) async -> DurableAuthState {
        let resolved = await authCoordinator.evaluateDurableAuthState()
        self.durableAuthState = resolved
        return resolved
    }

    public func evaluateAutoBootstrap(
        using authCoordinator: WalletAuthCoordinator,
        nodeIsStoppedOrError: Bool,
        isStartingUp: Bool,
        startAction: () async -> Bool
    ) async -> StartupBootstrapOutcome {
        let resolved = await refreshDurableState(using: authCoordinator)
        switch resolved {
        case .unknown:
            return .awaitingAuthResolution
        case .pristineUnenrolled:
            return .requiresInitialEnrollment
        case .corruptedOrMissingInEstablishedNode(let errorDescription):
            return .blockedCorruptedOrMissingRegistry(errorDescription)
        case .enrolled(let usernames):
            guard !usernames.isEmpty else {
                return .requiresInitialEnrollment
            }
            guard !hasCompletedAutoBootstrap,
                  !isBootstrapInFlight,
                  nodeIsStoppedOrError,
                  !isStartingUp else {
                return .alreadyBootstrappedOrActive
            }
            isBootstrapInFlight = true
            defer { isBootstrapInFlight = false }

            let started = await startAction()
            if started {
                hasCompletedAutoBootstrap = true
                return .startedNode(usernames: usernames)
            }
            return .nodeStartSkippedOrFailed
        }
    }

    public func authorizeNodeMutation(using authCoordinator: WalletAuthCoordinator) async -> NodeMutationAuthorization {
        let resolved = await refreshDurableState(using: authCoordinator)
        switch resolved {
        case .enrolled(let usernames) where !usernames.isEmpty:
            return NodeMutationAuthorization(allowed: true, durableState: resolved, reason: nil)
        case .unknown, .pristineUnenrolled, .enrolled:
            return NodeMutationAuthorization(
                allowed: false,
                durableState: resolved,
                reason: "Complete First-Time Operator Setup in the Wallet tab before starting or configuring the BTCB2 node."
            )
        case .corruptedOrMissingInEstablishedNode(let errorDescription):
            return NodeMutationAuthorization(
                allowed: false,
                durableState: resolved,
                reason: errorDescription
            )
        }
    }
}
