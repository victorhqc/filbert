import Core
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class DisplayLanguageModel {
    private(set) var locale = DisplayLanguage.locale
    private(set) var selectedLanguageCode = DisplayLanguage.selectedLanguageCode
    @ObservationIgnored private var localeObserverToken: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
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
        DisplayLanguage.selectedLanguageCode = languageCode
        selectedLanguageCode = languageCode
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
