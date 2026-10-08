import SwiftUI

typealias AllowanceForecastLineSource = @MainActor (Date) -> AllowanceForecastPresentation.Line?

struct AllowanceForecastTimeline<Content: View>: View {
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(context.date)
        }
    }
}

struct ForecastHeadline: View {
    let headline: AllowanceForecastPresentation.Headline

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headline.text)
                .font(.headline)
            Text(headline.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline.accessibilityLabel)
        .help(headline.accessibilityLabel)
    }
}

struct ForecastRowLine: View {
    let line: AllowanceForecastPresentation.Line

    var body: some View {
        Text(line.text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(line.accessibilityLabel)
            .help(line.accessibilityLabel)
    }
}
