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
                return .setup(DisplayText { String(displayLocalized: "Sign in to Gemini CLI", bundle: .module) })
            }
            return nil
        } catch GeminiCredentialError.itemNotFound {
            return .setup(DisplayText { String(displayLocalized: "Sign in to Gemini CLI", bundle: .module) })
        } catch GeminiCredentialError.accessDenied(errSecUserCanceled) {
            return .setup(DisplayText {
                String(displayLocalized: "Allow Filbert to read the Gemini CLI Keychain item", bundle: .module)
            })
        } catch let error as GeminiCredentialError where error == .invalidPayload {
            recordCredentialFailure(operation: "currentSetupState", error: error)
            return .error(DisplayText {
                String(displayLocalized: "Update Gemini CLI and sign in again", bundle: .module)
            })
        } catch let error as GeminiCredentialError {
            recordCredentialFailure(operation: "currentSetupState", error: error)
            return .error(DisplayText {
                String(displayLocalized: "Allow Filbert to read the Gemini CLI Keychain item", bundle: .module)
            })
        } catch is CancellationError {
            return .setup(DisplayText { String(displayLocalized: "Sign in to Gemini CLI", bundle: .module) })
        } catch let error as URLError where error.code == .cancelled {
            return .setup(DisplayText { String(displayLocalized: "Sign in to Gemini CLI", bundle: .module) })
        } catch {
            recordCredentialFailure(operation: "currentSetupState", error: error)
            return .error(DisplayText { String(displayLocalized: "Sign in to Gemini CLI", bundle: .module) })
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
