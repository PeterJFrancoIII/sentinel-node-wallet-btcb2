import AppKit
import AuthenticationServices
import Foundation

/// Uses Apple's system credential picker. The OS handles permission and any
/// Touch ID / device-password prompt; the app never reads the Passwords vault
/// directly. Apple requires a signed webcredentials associated-domain match.
@MainActor
final class AppleSavedPasswordCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var authorizationController: ASAuthorizationController?
    var onCredential: ((String, String) -> Void)?
    var onFailure: ((String) -> Void)?

    func requestSavedLogin() {
        let request = ASAuthorizationPasswordProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authorizationController = controller
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { authorizationController = nil }
        guard let credential = authorization.credential as? ASPasswordCredential else {
            onFailure?("Apple Passwords returned no password credential.")
            return
        }
        onCredential?(credential.user, credential.password)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { authorizationController = nil }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return // User dismissed the system credential picker.
        }
        onFailure?(
            "Apple Passwords could not supply a saved login. This app needs an owner-approved " +
            "webcredentials association and properly signed build. You can still sign in manually."
        )
    }
}
