@testable import App
import Core
import Foundation
import XCTest

final class MenuBarProviderSelectorTests: XCTestCase {
    func testManualSelectionUsesFirstConfiguredProvider() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["second", "first"],
                states: ["first": loadedState(for: "first")],
                isAutomatic: false
            ),
            "second"
        )
    }

    func testEmptyConfiguredProvidersSelectsNoProvider() {
        XCTAssertNil(providerId(configuredProviderIds: [], states: [:], isAutomatic: false))
        XCTAssertNil(providerId(configuredProviderIds: [], states: [:], isAutomatic: true))
    }

    func testAutomaticSelectionExcludesUnavailableAndNonDisplayableCandidates() {
        let states: [String: ProviderState] = [
            "displayable": loadedState(for: "displayable", updatedAt: 1),
            "fallback": loadedState(for: "fallback", updatedAt: 10, isDisplayable: false),
            "loading": .loading,
            "setup": .setup("Setup needed"),
            "error": .error("Unavailable"),
            "disabled": loadedState(for: "disabled", updatedAt: 100),
            "unlisted": loadedState(for: "unlisted", updatedAt: 1000),
        ]

        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["displayable", "fallback", "loading", "setup", "error", "disabled"],
                enabledProviderIds: ["displayable", "fallback", "loading", "setup", "error"],
                states: states,
                isAutomatic: true
            ),
            "displayable"
        )
    }

    func testAutomaticSelectionPrioritizesOneFastProviderOverNewerCandidates() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["fast", "newer"],
                states: [
                    "fast": loadedState(for: "fast", updatedAt: 1),
                    "newer": loadedState(for: "newer", updatedAt: 100),
                ],
                fastRefreshingProviderIds: ["fast"],
                isAutomatic: true
            ),
            "fast"
        )
    }

    func testAutomaticSelectionUsesSavedOrderBetweenFastProviders() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["first", "second"],
                states: [
                    "first": loadedState(for: "first", updatedAt: 1),
                    "second": loadedState(for: "second", updatedAt: 100),
                ],
                fastRefreshingProviderIds: ["first", "second"],
                isAutomatic: true
            ),
            "first"
        )
    }

    func testAutomaticSelectionUsesLatestUpdateWhenNoProviderIsFast() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["older", "newer"],
                states: [
                    "older": loadedState(for: "older", updatedAt: 1),
                    "newer": loadedState(for: "newer", updatedAt: 2),
                ],
                isAutomatic: true
            ),
            "newer"
        )
    }

    func testAutomaticSelectionUsesSavedOrderForEqualUpdates() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["first", "second"],
                states: [
                    "first": loadedState(for: "first", updatedAt: 1),
                    "second": loadedState(for: "second", updatedAt: 1),
                ],
                isAutomatic: true
            ),
            "first"
        )
    }

    func testDefensiveTieBreakingSortsUnlistedCandidatesLastThenByProviderID() {
        let timestamp = Date(timeIntervalSinceReferenceDate: 1)
        let listed = MenuBarProviderSelector.Candidate(
            providerId: "listed",
            lastUpdated: timestamp,
            configuredOrderIndex: 0
        )
        let unlisted = MenuBarProviderSelector.Candidate(
            providerId: "unlisted",
            lastUpdated: timestamp,
            configuredOrderIndex: .max
        )
        let alpha = MenuBarProviderSelector.Candidate(
            providerId: "alpha",
            lastUpdated: timestamp,
            configuredOrderIndex: .max
        )
        let beta = MenuBarProviderSelector.Candidate(
            providerId: "beta",
            lastUpdated: timestamp,
            configuredOrderIndex: .max
        )

        XCTAssertTrue(MenuBarProviderSelector.updatedCandidatePrecedes(listed, unlisted))
        XCTAssertTrue(MenuBarProviderSelector.updatedCandidatePrecedes(alpha, beta))
    }

    func testAutomaticSelectionFallsBackToFirstConfiguredProviderWhenNoCandidateIsDisplayable() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["fallback", "other"],
                states: [
                    "fallback": .loading,
                    "other": loadedState(for: "other", isDisplayable: false),
                ],
                isAutomatic: true
            ),
            "fallback"
        )
    }

    func testAutomaticSelectionReevaluatesWhenFastStatusChanges() {
        let states: [String: ProviderState] = [
            "fast": loadedState(for: "fast", updatedAt: 1),
            "newer": loadedState(for: "newer", updatedAt: 2),
        ]

        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["fast", "newer"],
                states: states,
                fastRefreshingProviderIds: ["fast"],
                isAutomatic: true
            ),
            "fast"
        )
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["fast", "newer"],
                states: states,
                isAutomatic: true
            ),
            "newer"
        )
    }

    private func providerId(
        configuredProviderIds: [String],
        enabledProviderIds: Set<String>? = nil,
        states: [String: ProviderState],
        fastRefreshingProviderIds: Set<String> = [],
        isAutomatic: Bool
    ) -> String? {
        MenuBarProviderSelector.providerId(
            configuredProviderIds: configuredProviderIds,
            enabledProviderIds: enabledProviderIds ?? Set(configuredProviderIds),
            providerStates: states,
            fastRefreshingProviderIds: fastRefreshingProviderIds,
            isAutomatic: isAutomatic
        )
    }

    private func loadedState(
        for providerId: String,
        updatedAt: TimeInterval = 0,
        isDisplayable: Bool = true
    ) -> ProviderState {
        let lines = isDisplayable ? [UsageLine(label: "Window", percentage: 20)] : []
        return .loaded(
            ProviderQuota(
                providerId: providerId,
                providerName: providerId,
                headline: "",
                lines: lines,
                lastUpdated: Date(timeIntervalSinceReferenceDate: updatedAt)
            )
        )
    }
}
