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

    func testAutomaticSelectionPrioritizesHigherActivityScore() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["fast", "newer"],
                states: [
                    "fast": loadedState(for: "fast", updatedAt: 1),
                    "newer": loadedState(for: "newer", updatedAt: 100),
                ],
                activityScores: ["fast": 30],
                isAutomatic: true
            ),
            "fast"
        )
    }

    func testAutomaticSelectionUsesSavedOrderBetweenEqualActivityScores() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["first", "second"],
                states: [
                    "first": loadedState(for: "first", updatedAt: 1),
                    "second": loadedState(for: "second", updatedAt: 100),
                ],
                activityScores: ["first": 30, "second": 30],
                isAutomatic: true
            ),
            "first"
        )
    }

    func testAutomaticSelectionUsesSavedOrderWhenScoresAreAtEquilibrium() {
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["older", "newer"],
                states: [
                    "older": loadedState(for: "older", updatedAt: 1),
                    "newer": loadedState(for: "newer", updatedAt: 2),
                ],
                isAutomatic: true
            ),
            "older"
        )
    }

    func testAutomaticSelectionUsesSavedOrderForEqualScores() {
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
        let listed = MenuBarProviderSelector.Candidate(
            providerId: "listed",
            effectiveActivityScore: 1,
            configuredOrderIndex: 0
        )
        let unlisted = MenuBarProviderSelector.Candidate(
            providerId: "unlisted",
            effectiveActivityScore: 1,
            configuredOrderIndex: .max
        )
        let alpha = MenuBarProviderSelector.Candidate(
            providerId: "alpha",
            effectiveActivityScore: 1,
            configuredOrderIndex: .max
        )
        let beta = MenuBarProviderSelector.Candidate(
            providerId: "beta",
            effectiveActivityScore: 1,
            configuredOrderIndex: .max
        )

        XCTAssertTrue(MenuBarProviderSelector.candidatePrecedes(listed, unlisted))
        XCTAssertTrue(MenuBarProviderSelector.candidatePrecedes(alpha, beta))
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

    func testAutomaticSelectionReevaluatesWhenScoresChange() {
        let states: [String: ProviderState] = [
            "fast": loadedState(for: "fast", updatedAt: 1),
            "newer": loadedState(for: "newer", updatedAt: 2),
        ]

        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["fast", "newer"],
                states: states,
                activityScores: ["fast": 10, "newer": 20],
                isAutomatic: true
            ),
            "newer"
        )
        XCTAssertEqual(
            providerId(
                configuredProviderIds: ["fast", "newer"],
                states: states,
                activityScores: ["fast": 30, "newer": 20],
                isAutomatic: true
            ),
            "fast"
        )
    }

    private func providerId(
        configuredProviderIds: [String],
        enabledProviderIds: Set<String>? = nil,
        states: [String: ProviderState],
        activityScores: [String: Double] = [:],
        isAutomatic: Bool
    ) -> String? {
        MenuBarProviderSelector.providerId(
            configuredProviderIds: configuredProviderIds,
            enabledProviderIds: enabledProviderIds ?? Set(configuredProviderIds),
            providerStates: states,
            effectiveActivityScores: activityScores,
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
