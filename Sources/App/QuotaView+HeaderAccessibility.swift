import Core

extension QuotaView {
    func headerAccessibilityLabel(
        info: ProviderInfo,
        state: ProviderState,
        collapsed: Bool,
        fastRefreshStatus: String?
    ) -> String {
        let headerLabel: String
        guard collapsed, case let .loaded(quota) = state else {
            headerLabel = info.displayName
            return headerAccessibilityLabel(headerLabel, fastRefreshStatus: fastRefreshStatus)
        }

        switch QuotaStatusResolver.resolve(for: quota) {
        case let .window(percentage):
            headerLabel = String(
                displayLocalized: "\(info.displayName): \(Int(percentage.rounded()))% used",
                bundle: .module
            )
        case let .balance(_, formattedAmount):
            headerLabel = String(displayLocalized: "\(info.displayName): \(formattedAmount) remaining", bundle: .module)
        case let .credits(formattedAmount):
            headerLabel = String(
                displayLocalized: "\(info.displayName): \(formattedAmount) credits remaining",
                bundle: .module
            )
        case .fallback:
            headerLabel = info.displayName
        }
        return headerAccessibilityLabel(headerLabel, fastRefreshStatus: fastRefreshStatus)
    }

    func headerAccessibilityLabel(_ headerLabel: String, fastRefreshStatus: String?) -> String {
        guard let fastRefreshStatus else { return headerLabel }
        return String.localizedStringWithFormat(
            String(displayLocalized: "Accessibility sentence format", bundle: .module),
            headerLabel,
            fastRefreshStatus
        )
    }
}
