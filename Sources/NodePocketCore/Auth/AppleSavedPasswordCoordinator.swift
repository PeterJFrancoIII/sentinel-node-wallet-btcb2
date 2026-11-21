import AppKit
import AuthenticationServices
import Foundation

/// Protocol abstracting authorization request execution for Apple Saved Passwords.
/// Allows deterministic unit testing and simulation of native picker callbacks (success, cancel, failure, timeout).
@MainActor
public protocol AppleSavedPasswordRequestExecuting: AnyObject {
    func executeRequest(
        isInteractive: Bool,
        onSuccess: @escaping (String, String) -> Void,
        onFailure: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    )
    func cancel()
}

/// Default system implementation connecting to ASAuthorizationController.
final class SystemAppleSavedPasswordRequestExecutor: NSObject,
    AppleSavedPasswordRequestExecuting,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var authorizationController: ASAuthorizationController?
    private var onSuccess: ((String, String) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    private var isInteractive: Bool = true

    func executeRequest(
        isInteractive: Bool,
        onSuccess: @escaping (String, String) -> Void,
        onFailure: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isInteractive = isInteractive
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        self.onCancel = onCancel

        let request = ASAuthorizationPasswordProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.authorizationController = controller
        controller.performRequests()
    }

    func cancel() {
        authorizationController?.delegate = nil
        authorizationController?.presentationContextProvider = nil
        authorizationController = nil
        onSuccess = nil
        onFailure = nil
        onCancel = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? NSWindow()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let successCb = onSuccess
        let failCb = onFailure
        defer {
            authorizationController = nil
            onSuccess = nil
            onFailure = nil
            onCancel = nil
        }
        guard let credential = authorization.credential as? ASPasswordCredential else {
            if isInteractive {
                failCb?("Apple Passwords returned no password credential.")
            }
            return
        }
        successCb?(credential.user, credential.password)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let cancelCb = onCancel
        let failCb = onFailure
        defer {
            authorizationController = nil
            onSuccess = nil
            onFailure = nil
            onCancel = nil
        }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationErrorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            cancelCb?()
            return
        }
        if isInteractive {
            failCb?(
                "Apple Passwords could not supply a saved login (\(error.localizedDescription)). " +
                "Sign in with your password to automatically save and auto-fill it from your Mac's Keychain on every launch."
            )
        }
    }
}

/// Uses Apple's system credential picker. The OS handles permission and any
/// Touch ID / device-password prompt; the app never reads the Passwords vault
/// directly. Apple requires a signed webcredentials associated-domain match.
@MainActor
public final class AppleSavedPasswordCoordinator {

    private var executor: AppleSavedPasswordRequestExecuting
    public var onCredential: ((String, String) -> Void)?
    public var onFailure: ((String) -> Void)?
    public var onCancel: (() -> Void)?
    public private(set) var isInteractive: Bool = true

    #if DEBUG
    public static var customExecutorFactory: (@MainActor () -> AppleSavedPasswordRequestExecuting)? = nil
    #endif

    public init(executor: AppleSavedPasswordRequestExecuting? = nil) {
        #if DEBUG
        if let custom = Self.customExecutorFactory?() {
            self.executor = custom
            return
        }
        #endif
        self.executor = executor ?? SystemAppleSavedPasswordRequestExecutor()
    }

    public func requestSavedLogin(isInteractive: Bool = true) {
        self.isInteractive = isInteractive
        executor.executeRequest(
            isInteractive: isInteractive,
            onSuccess: { [weak self] user, pass in
                guard let self = self else { return }
                let cb = self.onCredential
                self.clearCallbacks()
                cb?(user, pass)
            },
            onFailure: { [weak self] err in
                guard let self = self else { return }
                let cb = self.onFailure
                self.clearCallbacks()
                cb?(err)
            },
            onCancel: { [weak self] in
                guard let self = self else { return }
                let cb = self.onCancel
                self.clearCallbacks()
                cb?()
            }
        )
    }

    /// Explicitly cancels any active or in-flight credential picker request, nullifying delegates
    /// and callbacks to prevent stale credential delivery across operator changes.
    public func cancel() {
        executor.cancel()
        clearCallbacks()
    }

    private func clearCallbacks() {
        onCredential = nil
        onFailure = nil
        onCancel = nil
    }
}
