import Core
import Foundation
import Observation
import ZAIProvider

@MainActor
@Observable
final class QuotaViewModel {
    // MARK: - Configuration

    private let providerId: String
    private let keychain: Keychain
    private let registry: ProviderRegistry
    private let refreshInterval: TimeInterval = 300

    // MARK: - State

    private(set) var isConfigured: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var quota: ProviderQuota?
    private(set) var errorMessage: String?

    // MARK: - Auto-refresh (AC5: timer (ui 01))

    private var refreshLoop: Task<Void, Never>?

    // MARK: - Init

    init(
        providerId: String = "zai",
        keychain: Keychain = .shared,
        registry: ProviderRegistry
    ) {
        self.providerId = providerId
        self.keychain = keychain
        self.registry = registry
        isConfigured = (try? keychain.load(for: providerId)) != nil

        if isConfigured {
            startAutoRefresh()
            fetchQuota()
        }
    }

    // MARK: - Key management (AC1/AC2: save & clear (ui 01))

    func saveKey(_ key: String) throws {
        try keychain.save(key, for: providerId)
        isConfigured = true
        startAutoRefresh()
        fetchQuota()
    }

    func deleteKey() throws {
        try keychain.delete(for: providerId)
        isConfigured = false
        quota = nil
        errorMessage = nil
        stopAutoRefresh()
    }

    // MARK: - Fetch (AC5: manual refresh (ui 01))

    func fetchQuota() {
        guard isConfigured, !isLoading else { return }

        isLoading = true
        errorMessage = nil

        Task {
            let results = await registry.fetchAll()

            guard let result = results[providerId] else {
                isLoading = false
                return
            }

            switch result {
            case let .success(newQuota):
                quota = newQuota
            case let .failure(error):
                // If the key was removed externally, drop to unconfigured
                if error is KeychainError {
                    isConfigured = (try? keychain.load(for: providerId)) != nil
                }
                errorMessage = classifyError(error)
            }

            isLoading = false
        }
    }

    // MARK: - Error classification (AC6: error states (ui 01))

    private func classifyError(_ error: Error) -> String {
        if let zaiError = error as? ZAIError {
            switch zaiError {
            case .http(401):
                return String(localized: "Authentication failed. Check your API key.")
            case let .http(code) where code == 429:
                return String(localized: "Rate limited. Try again later.")
            case .network:
                return String(localized: "Network error. Check your connection.")
            case .decoding, .http:
                return String(localized: "Unexpected response from server.")
            case .missingKey:
                return String(localized: "No API key configured.")
            }
        }

        if error is KeychainError {
            return String(localized: "Keychain access failed.")
        }

        return error.localizedDescription
    }

    // MARK: - Auto-refresh loop (AC5: 5-minute interval (ui 01))

    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshLoop = Task { [weak self] in
            guard let self else { return }
            let interval = refreshInterval
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.fetchQuota()
                }
            }
        }
    }

    private func stopAutoRefresh() {
        refreshLoop?.cancel()
        refreshLoop = nil
    }
}
