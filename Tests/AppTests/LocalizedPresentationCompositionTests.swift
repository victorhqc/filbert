@testable import App
import Core
import XCTest

final class LocalizedPresentationCompositionTests: AllowanceForecastPresentationTestCase {
    func testSpanishUsageForecastsAcceptSingularAndPluralDurations() throws {
        for language in ["es-MX", "es-ES"] {
            DisplayLanguage.selectedLanguageCode = language
            for duration: TimeInterval in [60, 120, 3600] {
                let presentation = present(
                    fiveHour: estimated("five-hour", in: duration, span: 60, approximate: true),
                    weekly: estimated("weekly", in: duration, span: 60),
                    weeklyGroup: nil
                )
                let headline = try XCTUnwrap(presentation.headline)
                let row = try XCTUnwrap(presentation.rowLines["weekly"])
                let full = CoarseDurationFormatting.string(from: duration, unitsStyle: .full)
                let spoken = "Tiempo de uso restante al ritmo reciente: aprox. \(full), según \(span(60)) de historial"

                XCTAssertEqual(headline.status, "Tiempo de uso restante: aprox. \(abbreviated(duration))", language)
                XCTAssertEqual(headline.accessibilitySentences, [spoken, "El tiempo indicado es aproximado"], language)
                XCTAssertEqual(
                    row.text,
                    "Tiempo de uso restante: aprox. \(abbreviated(duration)) · \(span(60)) de historial",
                    language
                )
                XCTAssertEqual(row.accessibilityLabel, spoken, language)
            }
        }
    }

    func testSpanishRemainingTimeAcceptsSingularAndPluralDurations() throws {
        for language in ["es-MX", "es-ES"] {
            DisplayLanguage.selectedLanguageCode = language
            for duration: TimeInterval in [60, 120, 3600] {
                let line = UsageLine(
                    label: DisplayText(verbatim: "Weekly"),
                    percentage: 50,
                    resetDate: now.addingTimeInterval(duration),
                    windowDuration: UsageWindowDuration.week
                )
                let pace = try XCTUnwrap(BudgetPace(line: line, now: now))
                let text = PacedUsageLineText(pace: pace, forecast: nil)

                XCTAssertEqual(text.remainingTime, "Tiempo restante: \(abbreviated(duration))", language)
                XCTAssertEqual(
                    text.accessibilitySentences[1],
                    "Tiempo restante: \(CoarseDurationFormatting.string(from: duration, unitsStyle: .full))",
                    language
                )
            }
        }
    }

    func testDepletionForecastsKeepStandaloneDurationsInTheirOriginalCase() throws {
        for language in ["ru", "de-DE"] {
            DisplayLanguage.selectedLanguageCode = language
            for duration: TimeInterval in [60, 120, 2 * 24 * 3600] {
                let presentation = present(
                    fiveHour: averagePace("five-hour", remaining: duration),
                    weekly: averagePace("weekly", remaining: duration),
                    weeklyGroup: nil
                )
                let headline = try XCTUnwrap(presentation.headline)
                let row = try XCTUnwrap(presentation.rowLines["weekly"])
                let full = CoarseDurationFormatting.string(from: duration, unitsStyle: .full)
                let short = abbreviated(duration)
                let history = span(3600)
                let status = language == "ru"
                    ? "До исчерпания: примерно \(short)"
                    : "Reicht noch etwa \(short)"
                let rowText = language == "ru"
                    ? "\(status) · история: \(history)"
                    : "\(status) · \(history) Verlauf"
                let spoken = language == "ru"
                    ? "При среднем темпе до исчерпания: примерно \(full). Период наблюдения: \(history)."
                    : "Reicht bei deinem Durchschnittstempo noch etwa \(full), basierend auf \(history) Verlauf"

                XCTAssertEqual(headline.status, status, language)
                XCTAssertEqual(headline.accessibilitySentences, [spoken], language)
                XCTAssertEqual(row.text, rowText, language)
                XCTAssertEqual(row.accessibilityLabel, spoken, language)
            }
        }
    }

    func testPortugueseBalanceAnnouncementsUseAnAgreementNeutralLabel() {
        for language in ["pt-BR", "pt-PT"] {
            DisplayLanguage.selectedLanguageCode = language
            for amount in [1.0, 2.0] {
                let formatted = amount.formatted(.currency(code: "EUR").locale(DisplayLanguage.locale))
                let resolved = MenuBarProviderPresentation.Resolved(
                    providerName: "Provider",
                    glyph: .sfSymbol("dollarsign"),
                    status: .balance(amount: amount, formattedAmount: formatted),
                    isFastRefreshActive: false
                )

                let expected = language == "pt-BR"
                    ? "Provider: saldo restante: \(formatted)"
                    : "Provider: \(formatted) de saldo restante"

                XCTAssertEqual(MenuBarProviderPresentation.accessibilityLabel(for: resolved), expected, language)
            }
        }
    }

    func testChineseCodexCreditAnnouncementsUseTheProductTerm() {
        DisplayLanguage.selectedLanguageCode = "zh-Hans"
        let resolved = MenuBarProviderPresentation.Resolved(
            providerName: "Codex",
            glyph: .sfSymbol("sparkles"),
            status: .credits(formattedAmount: "1.00"),
            isFastRefreshActive: false
        )

        XCTAssertEqual(MenuBarProviderPresentation.accessibilityLabel(for: resolved), "Codex：剩余额度 1.00")

        DisplayLanguage.selectedLanguageCode = "zh-Hant"
        XCTAssertEqual(MenuBarProviderPresentation.accessibilityLabel(for: resolved), "Codex：剩餘點數1.00")
    }

    func testCreditChargePercentagesReferToTheStandardCharge() {
        let expected: [String: (fraction: (String) -> String, standard: String)] = [
            "de-DE": ({ "\($0) des Standard-Credit-Tarifs" }, "Standard-Credit-Tarif"),
            "zh-Hans": ({ "按标准的 \($0) 消耗积分" }, "标准积分消耗"),
            "zh-Hant": ({ "按標準的\($0)扣除點數" }, "標準點數扣除比例"),
        ]
        for (language, text) in expected {
            DisplayLanguage.selectedLanguageCode = language
            let percentage = 0.5.formatted(.percent.precision(.fractionLength(0 ... 1)).locale(DisplayLanguage.locale))

            XCTAssertEqual(
                PeakHoursPresentation.rateText(for: .fractionOfStandardRate(0.5)), text.fraction(percentage), language
            )
            XCTAssertEqual(PeakHoursPresentation.rateText(for: .fractionOfStandardRate(1)), text.standard, language)
        }
    }

    func testPercentageAnnouncementsFollowEachLocalesSymbolSpacing() {
        let expected = [
            "de-DE": "Provider: 50 % verwendet",
            "es-ES": "Provider: 50 % usado",
            "es-MX": "Provider: 50% usado",
        ]
        for (language, text) in expected {
            DisplayLanguage.selectedLanguageCode = language
            let resolved = MenuBarProviderPresentation.Resolved(
                providerName: "Provider",
                glyph: .sfSymbol("sparkles"),
                status: .window(percentage: 50),
                isFastRefreshActive: false
            )

            XCTAssertEqual(MenuBarProviderPresentation.accessibilityLabel(for: resolved), text, language)
        }
    }

    private func averagePace(_ id: String, remaining: TimeInterval) -> AllowanceForecast {
        AllowanceForecast(
            usageLineId: id,
            state: .estimated(depletesAt: now.addingTimeInterval(remaining)),
            observedAt: now,
            evidenceSpan: 3600,
            pace: .periodAverage
        )
    }
}
