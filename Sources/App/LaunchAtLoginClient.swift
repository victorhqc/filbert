import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unavailable

    init(nativeStatus: SMAppService.Status) {
        switch nativeStatus {
        case .notRegistered:
            self = .notRegistered
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        @unknown default:
            self = .unavailable
        }
    }
}

@MainActor
protocol LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

enum LaunchAtLoginEligibility {
    static func isEligible(bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension == "app"
            && bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL"
            && bundle.bundleIdentifier?.isEmpty == false
    }
}

@MainActor
struct SystemLaunchAtLoginClient: LaunchAtLoginManaging {
    private let service: SMAppService? = LaunchAtLoginEligibility.isEligible(bundle: .main)
        ? SMAppService.mainApp
        : nil

    var status: LaunchAtLoginStatus {
        guard let service else { return .unavailable }

        return LaunchAtLoginStatus(nativeStatus: service.status)
    }

    func register() throws {
        guard let service else { throw LaunchAtLoginClientError.unavailable }

        try service.register()
    }

    func unregister() throws {
        guard let service else { throw LaunchAtLoginClientError.unavailable }

        try service.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private enum LaunchAtLoginClientError: Error {
    case unavailable
}
