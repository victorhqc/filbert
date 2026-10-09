import Core
import Foundation

struct AllowanceForecastPresentation: Equatable {
    struct Headline: Equatable {
        /// Set when the binding line is not the line the headline names.
        let label: String?
        let value: String
        let status: String
        let detail: String?
        /// Read after the subject, in order.
        let accessibilitySentences: [String]

        var subject: String {
            Self.subject(label: label, value: value)
        }

        var accessibilityLabel: String {
            AllowanceForecastPresentation.joinedSentences([subject] + accessibilitySentences)
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

    static let longestDisplayedEstimate: TimeInterval = 4 * 7 * 24 * 60 * 60

    static func joinedSentences(_ sentences: [String]) -> String {
        sentences.dropFirst().reduce(sentences.first ?? "") { joined, sentence in
            String.localizedStringWithFormat(String(localized: "Accessibility sentence format"), joined, sentence)
        }
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
    enum HeadlineReason {
        case limitReached
        case forecast(AllowanceForecast)
    }

    struct HeadlineBinding {
        let line: UsageLine
        let reason: HeadlineReason
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
        func binding(_ line: UsageLine, _ reason: HeadlineReason) -> HeadlineBinding {
            HeadlineBinding(line: line, reason: reason, showsLabel: line.id != headlineId)
        }

        if let blockedLine = limitReachedLine(in: groupLines) {
            return binding(blockedLine, .limitReached)
        }

        let groupForecasts = groupLines.compactMap { line in
            line.id.flatMap { forecasts[$0] }.map { (line: line, forecast: $0) }
        }
        guard !groupForecasts.contains(where: \.forecast.isUncertainNearLimit) else { return nil }

        let earliest = groupForecasts
            .compactMap { entry in entry.forecast.depletesAt.map { (entry: entry, depletesAt: $0) } }
            .min { $0.depletesAt < $1.depletesAt }?
            .entry
        if let earliest {
            return binding(earliest.line, .forecast(earliest.forecast))
        }

        guard let headlineForecast = forecasts[headlineId], headlineForecast.isBeyondReset else {
            return nil
        }
        return binding(headlineLine, .forecast(headlineForecast))
    }

    /// The line that resets last blocks usage longest.
    static func limitReachedLine(in lines: [UsageLine]) -> UsageLine? {
        lines
            .filter { line in QuotaStatusResolver.percentage(for: line).map { $0 >= 100 } ?? false }
            .max { ($0.resetDate ?? .distantFuture) < ($1.resetDate ?? .distantFuture) }
    }

    static func headline(for binding: HeadlineBinding, now: Date) -> Headline? {
        guard let value = valueText(for: binding.line) else { return nil }
        let label = binding.showsLabel ? binding.line.label : nil

        let status: String
        let detail: String?
        let sentences: [String]
        switch binding.reason {
        case .limitReached:
            status = String(localized: "Limit reached")
            detail = binding.line.resetDate.map(QuotaFormatting.countdown(to:))
            sentences = [String(localized: "Limit reached, no more use available until reset"), detail]
                .compactMap(\.self)
        case let .forecast(forecast):
            let span = CoarseDurationFormatting.evidenceSpan(forecast.evidenceSpan ?? 0)
            switch forecast.state {
            case .estimated:
                status = RemainingUse(forecast, now: now).headlineStatus
                detail = String.localizedStringWithFormat(String(localized: "Based on the last %@"), span)
            case .beyondReset:
                status = String(localized: "Not expected to run out")
                detail = String(localized: "before reset at recent pace")
            case .learning, .quiet, .tooFarApart, .paused, .exhausted, .insufficient:
                return nil
            }
            sentences = accessibilitySentences(for: forecast, now: now) ?? [status]
        }

        return Headline(label: label, value: value, status: status, detail: detail, accessibilitySentences: sentences)
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
            text = RemainingUse(forecast, now: now).rowText(span: span)
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
        let sentences = accessibilitySentences(for: forecast, now: now) ?? [text]
        return Line(text: text, accessibilityLabel: joinedSentences(sentences))
    }

    static func accessibilitySentences(for forecast: AllowanceForecast, now: Date) -> [String]? {
        let span = CoarseDurationFormatting.evidenceSpan(forecast.evidenceSpan ?? 0)
        let sentence: String
        switch forecast.state {
        case .estimated:
            sentence = RemainingUse(forecast, now: now).accessibilitySentence(span: span)
        case .beyondReset:
            sentence = String.localizedStringWithFormat(
                String(localized: "Not expected to run out before reset at recent pace, based on the last %@"),
                span
            )
        case .learning, .quiet, .tooFarApart, .paused, .exhausted, .insufficient:
            return nil
        }
        guard forecast.isApproximate else { return [sentence] }
        return [sentence, String(localized: "Timing is approximate")]
    }
}

private struct RemainingUse {
    let duration: TimeInterval
    let exceedsLongestDisplayedEstimate: Bool

    init(_ forecast: AllowanceForecast, now: Date) {
        let remaining = max(forecast.remainingUse(at: now) ?? 0, 60)
        let longest = AllowanceForecastPresentation.longestDisplayedEstimate
        duration = min(remaining, longest)
        exceedsLongestDisplayedEstimate = remaining > longest
    }

    var headlineStatus: String {
        let format = exceedsLongestDisplayedEstimate
            ? String(localized: "More than %@ of use remaining")
            : String(localized: "About %@ of use remaining")
        return String.localizedStringWithFormat(format, CoarseDurationFormatting.string(from: duration))
    }

    func rowText(span: String) -> String {
        let format = exceedsLongestDisplayedEstimate
            ? String(localized: "More than %1$@ of use remaining · last %2$@")
            : String(localized: "About %1$@ of use remaining · last %2$@")
        return String.localizedStringWithFormat(format, CoarseDurationFormatting.string(from: duration), span)
    }

    func accessibilitySentence(span: String) -> String {
        let format = exceedsLongestDisplayedEstimate
            ? String(localized: "More than %1$@ of use remaining at recent pace, based on the last %2$@")
            : String(localized: "About %1$@ of use remaining at recent pace, based on the last %2$@")
        return String.localizedStringWithFormat(
            format,
            CoarseDurationFormatting.string(from: duration, unitsStyle: .full),
            span
        )
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
