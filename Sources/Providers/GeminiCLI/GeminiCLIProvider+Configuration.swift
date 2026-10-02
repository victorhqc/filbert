import Core
import Foundation
import Security

public extension GeminiCLIProvider {
    func isConfigured() -> Bool {
        do {
            guard let credentials = try credentialStore.load() else { return false }
            return credentials.accessToken?.isEmpty == false
                || credentials.refreshToken?.isEmpty == false
        } catch {
            recordCredentialFailure(operation: "isConfigured", error: error)
            return false
        }
    }

    func currentSetupState() async -> ProviderState? {
        do {
            guard let credentials = try credentialStore.load(),
                  credentials.accessToken?.isEmpty == false
                  || credentials.refreshToken?.isEmpty == false
            else {
                return .setup(String(localized: "Sign in to Gemini CLI"))
            }
            return nil
        } catch GeminiCredentialError.itemNotFound {
            return .setup(String(localized: "Sign in to Gemini CLI"))
        } catch GeminiCredentialError.accessDenied(errSecUserCanceled) {
            return .setup(
                String(localized: "Allow Filbert to read the Gemini CLI Keychain item")
            )
        } catch let error as GeminiCredentialError where error == .invalidPayload {
            recordCredentialFailure(operation: "currentSetupState", error: error)
            return .error(
                String(localized: "Update Gemini CLI and sign in again")
            )
        } catch let error as GeminiCredentialError {
            recordCredentialFailure(operation: "currentSetupState", error: error)
            return .error(
                String(localized: "Allow Filbert to read the Gemini CLI Keychain item")
            )
        } catch is CancellationError {
            return .setup(String(localized: "Sign in to Gemini CLI"))
        } catch let error as URLError where error.code == .cancelled {
            return .setup(String(localized: "Sign in to Gemini CLI"))
        } catch {
            recordCredentialFailure(operation: "currentSetupState", error: error)
            return .error(String(localized: "Sign in to Gemini CLI"))
        }
    }

    private func recordCredentialFailure(operation: String, error: any Error) {
        guard !(error is CancellationError),
              (error as? URLError)?.code != .cancelled
        else { return }
        if let credentialError = error as? GeminiCredentialError {
            switch credentialError {
            case .itemNotFound, .accessDenied(errSecUserCanceled):
                return
            case .invalidPayload, .accessDenied:
                break
            }
        }
        errorLog.record(
            component: "GeminiCLIProvider",
            operation: operation,
            code: "credential_read_failed",
            providerID: Self.providerId
        )
    }
}
