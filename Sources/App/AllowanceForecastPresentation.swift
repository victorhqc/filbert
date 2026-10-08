import Core
import Foundation

/// Only estimated and beyond-reset forecasts change the title.
struct AllowanceForecastPresentation: Equatable {
    struct Title: Equatable {
        /// Set when the binding line is not the line the title names.
        let label: String?
        let value: String
        let status: String
        let detail: String
        let accessibilityLabel: String

        var subject: String {
            Self.subject(label: label, value: value)
        }

        var text: String {
            String.localizedStringWithFormat(String(localized: "Forecast title format"), subject, status)
        }

        static func subject(label: String?, value: String) -> String {
            guard let label else { return value }
            return String.localizedStringWithFormat(String(localized: "Forecast labeled value format"), label, value)
        }
    }

    struct Line: Equatable {
        let text: String
        let accessibilityLabel: String
    }

    static let empty = AllowanceForecastPresentation(title: nil, rowLines: [:])

    let title: Title?
    /// Keyed by usage line ID.
    let rowLines: [String: Line]

    init(title: Title?, rowLines: [String: Line]) {
        self.title = title
        self.rowLines = rowLines
    }

    init(quota: ProviderQuota, forecasts: [String: AllowanceForecast], now: Date) {
        let binding = Self.titleBinding(quota: quota, forecasts: forecasts)
        let title = binding.flatMap { Self.title(for: $0, now: now) }
        self.title = title

        var rowLines: [String: Line] = [:]
        for line in quota.lines {
            guard let id = line.id,
                  title == nil || id != binding?.line.id,
                  let forecast = forecasts[id],
                  let rowLine = Self.rowLine(for: forecast, now: now)
            else {
                continue
            }
            rowLines[id] = rowLine
        }
        self.rowLines = rowLines
    }
}

private extension AllowanceForecastPresentation {
    struct TitleBinding {
        let line: UsageLine
        let forecast: AllowanceForecast
        let showsLabel: Bool
    }

    /// The earliest estimate in the limit group binds. Other pools never compete.
    static func titleBinding(quota: ProviderQuota, forecasts: [String: AllowanceForecast]) -> TitleBinding? {
        guard let headlineId = quota.headlineUsageLineId,
              let headlineLine = quota.lines.first(where: { $0.id == headlineId })
        else {
            return nil
        }
        let groupLines = headlineLine.limitGroup.map { group in
            quota.lines.filter { $0.limitGroup == group }
        } ?? [headlineLine]
        let groupForecasts = groupLines.compactMap { line in
            line.id.flatMap { forecasts[$0] }.map { (line: line, forecast: $0) }
        }
        guard !groupForecasts.isEmpty,
              !groupForecasts.contains(where: { $0.forecast.state == .exhausted })
        else {
            return nil
        }

        let earliest = groupForecasts
            .compactMap { entry in entry.forecast.depletesAt.map { (entry: entry, depletesAt: $0) } }
            .min { $0.depletesAt < $1.depletesAt }?
            .entry
        if let earliest {
            return TitleBinding(
                line: earliest.line,
                forecast: earliest.forecast,
                showsLabel: earliest.line.id != headlineId
            )
        }

        guard groupForecasts.allSatisfy(\.forecast.isBeyondReset) else { return nil }
        let forecast = forecasts[headlineId] ?? groupForecasts[0].forecast
        return TitleBinding(line: headlineLine, forecast: forecast, showsLabel: false)
    }

    static func title(for binding: TitleBinding, now: Date) -> Title? {
        guard let value = valueText(for: binding.line) else { return nil }
        let span = binding.forecast.evidenceSpan ?? 0

        let status: String
        let detail: String
        switch binding.forecast.state {
        case .estimated:
            status = String.localizedStringWithFormat(
                String(localized: "About %@ of use remaining"),
                CoarseDurationFormatting.string(from: clampedRemaining(binding.forecast, now: now))
            )
            detail = String.localizedStringWithFormat(
                String(localized: "Based on the last %@"),
                CoarseDurationFormatting.evidenceSpan(span)
            )
        case .beyondReset:
            status = String(localized: "Not expected to run out")
            detail = String(localized: "before reset at recent pace")
        case .learning, .quiet, .tooFarApart, .paused, .exhausted, .insufficient:
            return nil
        }

        let label = binding.showsLabel ? binding.line.label : nil
        return Title(
            label: label,
            value: value,
            status: status,
            detail: detail,
            accessibilityLabel: String.localizedStringWithFormat(
                String(localized: "Accessibility sentence format"),
                Title.subject(label: label, value: value),
                accessibilitySentence(for: binding.forecast, now: now) ?? status
            )
        )
    }

    static func valueText(for line: UsageLine) -> String? {
        if let percentage = QuotaStatusResolver.percentage(for: line), percentage.isFinite {
            return String(format: "%.0f%%", percentage)
        }
        return QuotaStatusResolver.amountText(for: line)
    }
}

private extension AllowanceForecastPresentation {
    static func rowLine(for forecast: AllowanceForecast, now: Date) -> Line? {
        let span = CoarseDurationFormatting.evidenceSpan(forecast.evidenceSpan ?? 0)
        let text: String
        switch forecast.state {
        case .estimated:
            text = String.localizedStringWithFormat(
                String(localized: "About %1$@ of use remaining · last %2$@"),
                CoarseDurationFormatting.string(from: clampedRemaining(forecast, now: now)),
                span
            )
        case .beyondReset:
            text = String.localizedStringWithFormat(
                String(localized: "Not expected to run out before reset · last %@"),
                span
            )
        case .learning:
            text = String(localized: "Learning your usage rate…")
        case .quiet:
            text = String(localized: "No recent consumption detected")
        case .tooFarApart:
            text = String(localized: "Updates too far apart to estimate")
        case .paused:
            text = String(localized: "Forecast paused until fresh data arrives")
        case .exhausted, .insufficient:
            return nil
        }
        return Line(text: text, accessibilityLabel: accessibilitySentence(for: forecast, now: now) ?? text)
    }

    /// VoiceOver gets the full sentence, not the abbreviated visible text.
    static func accessibilitySentence(for forecast: AllowanceForecast, now: Date) -> String? {
        let span = CoarseDurationFormatting.evidenceSpan(forecast.evidenceSpan ?? 0)
        let sentence: String
        switch forecast.state {
        case .estimated:
            sentence = String.localizedStringWithFormat(
                String(localized: "About %1$@ of use remaining at recent pace, based on the last %2$@"),
                CoarseDurationFormatting.string(from: clampedRemaining(forecast, now: now), unitsStyle: .full),
                span
            )
        case .beyondReset:
            sentence = String.localizedStringWithFormat(
                String(localized: "Not expected to run out before reset at recent pace, based on the last %@"),
                span
            )
        case .learning, .quiet, .tooFarApart, .paused, .exhausted, .insufficient:
            return nil
        }
        guard forecast.isApproximate else { return sentence }
        return String.localizedStringWithFormat(
            String(localized: "Accessibility sentence format"),
            sentence,
            String(localized: "Timing is approximate")
        )
    }

    static func clampedRemaining(_ forecast: AllowanceForecast, now: Date) -> TimeInterval {
        max(forecast.remainingUse(at: now) ?? 0, 60)
    }
}

private extension AllowanceForecast {
    var depletesAt: Date? {
        guard case let .estimated(depletesAt) = state else { return nil }
        return depletesAt
    }

    var isBeyondReset: Bool {
        guard case .beyondReset = state else { return false }
        return true
    }
}
