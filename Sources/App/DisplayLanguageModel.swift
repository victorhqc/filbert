import Core
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class DisplayLanguageModel {
    private(set) var locale: Locale
    private(set) var selectedLanguageCode: String?
    @ObservationIgnored private let preference: AppLanguagePreference
    @ObservationIgnored private var localeObserverToken: NSObjectProtocol?

    init(
        preference: AppLanguagePreference = AppLanguagePreference(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.preference = preference
        DisplayLanguage.setSystemPreferences { preference.systemLanguages() }
        let stored = preference.selectedLanguageCode
        DisplayLanguage.selectedLanguageCode = stored
        selectedLanguageCode = stored
        locale = DisplayLanguage.locale
        localeObserverToken = notificationCenter.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func select(_ languageCode: String?) {
        preference.store(languageCode)
        DisplayLanguage.selectedLanguageCode = languageCode
        if languageCode != selectedLanguageCode {
            selectedLanguageCode = languageCode
        }
        refresh()
    }

    /// With no selection, the display language follows the macOS language order.
    func refresh() {
        let current = DisplayLanguage.locale
        if current != locale {
            locale = current
        }
    }
}

/// A new identity rebuilds every view below it, so all text resolves again in the new language.
struct DisplayLanguageRoot<Content: View>: View {
    let model: DisplayLanguageModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .id(model.locale)
            .environment(\.locale, model.locale)
    }
}
