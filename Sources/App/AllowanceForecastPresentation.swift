import Core
import Foundation

struct AllowanceForecastPresentation: Equatable {
    struct Headline: Equatable {
        /// Set when the binding line is not the line the headline names.
        let label: String?
        let value: String
        let status: String
        let detail: String
        let accessibilityLabel: String

        var subject: String {
            Self.subject(label: label, value: value)
        }

        var text: String {
            String.localizedStringWithFormat(String(localized: "Forecast headline format"), subject, status)
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

    let headline: Headline?
    /// Keyed by usage line ID.
    let rowLines: [String: Line]

    init(quota: ProviderQuota, forecasts: [String: AllowanceForecast], now: Date) {
        let binding = Self.headlineBinding(quota: quota, forecasts: forecasts)
        let headline = binding.flatMap { Self.headline(for: $0, now: now) }
        self.headline = headline

        var rowLines: [String: Line] = [:]
        for line in quota.lines {
            guard let id = line.id,
                  headline == nil || id != binding?.line.id,
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
    struct HeadlineBinding {
        let line: UsageLine
        let forecast: AllowanceForecast
        let showsLabel: Bool
    }

    static func headlineBinding(quota: ProviderQuota, forecasts: [String: AllowanceForecast]) -> HeadlineBinding? {
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
            return HeadlineBinding(
                line: earliest.line,
                forecast: earliest.forecast,
                showsLabel: earliest.line.id != headlineId
            )
        }

        guard groupForecasts.allSatisfy(\.forecast.isBeyondReset) else { return nil }
        let forecast = forecasts[headlineId] ?? groupForecasts[0].forecast
        return HeadlineBinding(line: headlineLine, forecast: forecast, showsLabel: false)
    }

    static func headline(for binding: HeadlineBinding, now: Date) -> Headline? {
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
        return Headline(
            label: label,
            value: value,
            status: status,
            detail: detail,
            accessibilityLabel: String.localizedStringWithFormat(
                String(localized: "Accessibility sentence format"),
                Headline.subject(label: label, value: value),
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
