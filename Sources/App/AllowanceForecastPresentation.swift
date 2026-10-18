import Core
import Foundation

struct AllowanceForecastPresentation: Equatable {
    struct Headline: Equatable {
        /// Names a pool that stands in for the headline line.
        let label: String?
        let value: String
        let status: String?
        let detail: String?
        /// Read after the subject, in order.
        let accessibilitySentences: [String]

        var subject: String {
            guard let label else { return value }
            return String.localizedStringWithFormat(
                String(displayLocalized: "Promoted pool value format", bundle: .module),
                label,
                value
            )
        }

        var accessibilityLabel: String {
            AllowanceForecastPresentation.joinedSentences([subject] + accessibilitySentences)
        }

        var text: String {
            guard let status else { return subject }
            return String.localizedStringWithFormat(
                String(displayLocalized: "Forecast headline format", bundle: .module),
                subject,
                status
            )
        }
    }

    struct Line: Equatable {
        let text: String
        let accessibilityLabel: String
    }

    static let longestDisplayedEstimate: TimeInterval = 4 * 7 * 24 * 60 * 60

    static func joinedSentences(_ sentences: [String]) -> String {
        sentences.dropFirst().reduce(sentences.first ?? "") { joined, sentence in
            String.localizedStringWithFormat(
                String(displayLocalized: "Accessibility sentence format", bundle: .module),
                joined,
                sentence
            )
        }
    }

    let headline: Headline?
    /// Keyed by usage line ID.
    let rowLines: [String: Line]

    init(quota: ProviderQuota, forecasts: [String: AllowanceForecast], now: Date) {
        let fallbackPool = FallbackPoolLayout(lines: quota.lines)
        let headlineLine = fallbackPool?.pool
            ?? quota.headlineUsageLineId.flatMap { id in quota.lines.first { $0.id == id } }
        let headline = if let fallbackPool {
            Self.poolHeadline(for: fallbackPool, forecasts: forecasts, now: now)
        } else {
            headlineLine.flatMap { line in
                Self.headlineReason(for: line, forecasts: forecasts).flatMap { reason in
                    Self.headline(for: line, reason: reason, now: now)
                }
            }
        }
        self.headline = headline

        let headlineShowsItsForecast = fallbackPool == nil ? headline != nil : headline?.status != nil
        var rowLines: [String: Line] = [:]
        for line in quota.lines {
            guard let id = line.id, !headlineShowsItsForecast || id != headlineLine?.id else { continue }
            if let headlineLine, Self.isOtherGroupLineAtLimit(line, headlineLine: headlineLine) {
                rowLines[id] = Self.limitReachedRowLine
            } else if let forecast = forecasts[id], let rowLine = Self.rowLine(for: forecast, now: now) {
                rowLines[id] = rowLine
            }
        }
        self.rowLines = rowLines
    }
}

private extension AllowanceForecastPresentation {
    enum HeadlineReason {
        case limitReached
        case forecast(AllowanceForecast)
    }

    static func headlineReason(for line: UsageLine, forecasts: [String: AllowanceForecast]) -> HeadlineReason? {
        if QuotaStatusResolver.isAtLimit(line) {
            return .limitReached
        }
        guard let forecast = line.id.flatMap({ forecasts[$0] }), !forecast.isUncertainNearLimit else {
            return nil
        }
        return .forecast(forecast)
    }

    static func isOtherGroupLineAtLimit(_ line: UsageLine, headlineLine: UsageLine) -> Bool {
        line.id != headlineLine.id
            && line.limitGroup != nil
            && line.limitGroup == headlineLine.limitGroup
            && QuotaStatusResolver.isAtLimit(line)
    }

    static var limitReachedRowLine: Line {
        Line(
            text: String(displayLocalized: "Limit reached", bundle: .module),
            accessibilityLabel: String(
                displayLocalized: "Limit reached, no more use available until reset",
                bundle: .module
            )
        )
    }

    static func headline(for line: UsageLine, reason: HeadlineReason, now: Date) -> Headline? {
        guard let value = valueText(for: line) else { return nil }

        let status: String
        let detail: String?
        let sentences: [String]
        switch reason {
        case .limitReached:
            status = String(displayLocalized: "Limit reached", bundle: .module)
            detail = line.resetDate.map(QuotaFormatting.countdown(to:))
            sentences = [String(
                displayLocalized: "Limit reached, no more use available until reset",
                bundle: .module
            ), detail]
                .compactMap(\.self)
        case let .forecast(forecast):
            let span = CoarseDurationFormatting.evidenceSpan(forecast.evidenceSpan ?? 0)
            switch forecast.state {
            case .estimated:
                status = RemainingUse(forecast, now: now).headlineStatus
                detail = forecast.pace == .periodAverage
                    ? String.localizedStringWithFormat(
                        String(displayLocalized: "At your average pace over the last %@", bundle: .module),
                        span
                    )
                    : String.localizedStringWithFormat(
                        String(displayLocalized: "Based on the last %@", bundle: .module),
                        span
                    )
            case .beyondReset:
                status = String(displayLocalized: "Should last until reset", bundle: .module)
                detail = forecast.pace == .periodAverage
                    ? String.localizedStringWithFormat(
                        String(displayLocalized: "At your average pace over the last %@", bundle: .module),
                        span
                    )
                    : String.localizedStringWithFormat(
                        String(displayLocalized: "At your pace over the last %@", bundle: .module),
                        span
                    )
            case .learning, .quiet, .tooFarApart, .paused, .exhausted, .insufficient:
                return nil
            }
            sentences = accessibilitySentences(for: forecast, now: now) ?? [status]
        }

        return Headline(label: nil, value: value, status: status, detail: detail, accessibilitySentences: sentences)
    }

    static func poolHeadline(
        for layout: FallbackPoolLayout,
        forecasts: [String: AllowanceForecast],
        now: Date
    ) -> Headline? {
        guard let value = valueText(for: layout.pool) else { return nil }
        let forecastHeadline = headlineReason(for: layout.pool, forecasts: forecasts).flatMap { reason in
            headline(for: layout.pool, reason: reason, now: now)
        }
        let inUse = String.localizedStringWithFormat(
            String(displayLocalized: "Using %@", bundle: .module),
            layout.pool.label.resolved
        )
        return Headline(
            label: layout.pool.label.resolved,
            value: value,
            status: forecastHeadline?.status,
            detail: forecastHeadline?.detail,
            accessibilitySentences: [inUse]
                + layout.exhaustedLines.map(limitReachedSentence(for:))
                + (forecastHeadline?.accessibilitySentences ?? [])
        )
    }

    static func limitReachedSentence(for line: UsageLine) -> String {
        guard let resetDate = line.resetDate else {
            return String.localizedStringWithFormat(
                String(displayLocalized: "%@ limit reached", bundle: .module),
                line.label.resolved
            )
        }
        return String.localizedStringWithFormat(
            String(displayLocalized: "%1$@ limit reached, %2$@", bundle: .module),
            line.label.resolved,
            QuotaFormatting.countdown(to: resetDate)
        )
    }

    static func valueText(for line: UsageLine) -> String? {
        if let percentage = QuotaStatusResolver.percentage(for: line), percentage.isFinite {
            return QuotaFormatting.percentage(percentage)
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
                String(displayLocalized: "Should last until reset · last %@", bundle: .module),
                span
            )
        case .learning:
            text = String(displayLocalized: "Learning your usage rate…", bundle: .module)
        case .quiet:
            text = String(displayLocalized: "No recent consumption detected", bundle: .module)
        case .tooFarApart:
            text = String(displayLocalized: "Updates too far apart to estimate", bundle: .module)
        case .paused:
            text = String(displayLocalized: "Forecast paused until fresh data arrives", bundle: .module)
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
            let format = forecast.pace == .periodAverage
                ? String(
                    displayLocalized: "Should last until reset at your average pace over the last %@",
                    bundle: .module
                )
                : String(displayLocalized: "Should last until reset at your pace over the last %@", bundle: .module)
            sentence = String.localizedStringWithFormat(format, span)
        case .learning, .quiet, .tooFarApart, .paused, .exhausted, .insufficient:
            return nil
        }
        guard forecast.isApproximate else { return [sentence] }
        return [sentence, String(displayLocalized: "Timing is approximate", bundle: .module)]
    }
}

private struct RemainingUse {
    let duration: TimeInterval
    let exceedsLongestDisplayedEstimate: Bool
    /// From the average pace, which includes breaks, so the duration is calendar time.
    let isCalendarTime: Bool

    init(_ forecast: AllowanceForecast, now: Date) {
        let remaining = max(forecast.remainingUse(at: now) ?? 0, 60)
        let longest = AllowanceForecastPresentation.longestDisplayedEstimate
        isCalendarTime = forecast.pace == .periodAverage
        // A calendar-time estimate ends before its reset, so it needs no cap.
        duration = isCalendarTime ? remaining : min(remaining, longest)
        exceedsLongestDisplayedEstimate = !isCalendarTime && remaining > longest
    }

    var headlineStatus: String {
        let format = if isCalendarTime {
            String(displayLocalized: "Runs out in about %@", bundle: .module)
        } else if exceedsLongestDisplayedEstimate {
            String(displayLocalized: "More than %@ of use remaining", bundle: .module)
        } else {
            String(displayLocalized: "About %@ of use remaining", bundle: .module)
        }
        return String.localizedStringWithFormat(format, CoarseDurationFormatting.string(from: duration))
    }

    func rowText(span: String) -> String {
        let format = if isCalendarTime {
            String(displayLocalized: "Runs out in about %1$@ · last %2$@", bundle: .module)
        } else if exceedsLongestDisplayedEstimate {
            String(displayLocalized: "More than %1$@ of use remaining · last %2$@", bundle: .module)
        } else {
            String(displayLocalized: "About %1$@ of use remaining · last %2$@", bundle: .module)
        }
        return String.localizedStringWithFormat(format, CoarseDurationFormatting.string(from: duration), span)
    }

    func accessibilitySentence(span: String) -> String {
        let format = if isCalendarTime {
            String(displayLocalized: "Runs out in about %1$@ at your average pace over the last %2$@", bundle: .module)
        } else if exceedsLongestDisplayedEstimate {
            String(
                displayLocalized: "More than %1$@ of use remaining at recent pace, based on the last %2$@",
                bundle: .module
            )
        } else {
            String(
                displayLocalized: "About %1$@ of use remaining at recent pace, based on the last %2$@",
                bundle: .module
            )
        }
        return String.localizedStringWithFormat(
            format,
            CoarseDurationFormatting.string(from: duration, unitsStyle: .full),
            span
        )
    }
}
