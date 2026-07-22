import Core
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AppearanceTab: View {
    let viewModel: QuotaViewModel
    @State private var isVintageMacEnabled = VintageMacIcon.isEnabled
    @State private var draggedProviderId: String?

    var body: some View {
        SettingsScrollColumn {
            SettingsCard(
                heading: String(localized: "Provider order"),
                description: String(localized: "Drag providers to change their order.")
            ) {
                providerOrderRows
            }

            SettingsCard(heading: String(localized: "Balance thresholds")) {
                BalanceThresholdsSettingsRow()
            }

            SettingsCard(heading: String(localized: "Menu bar icon")) {
                Toggle(isOn: $isVintageMacEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Vintage Mac"))
                        Text(vintageMacSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: isVintageMacEnabled) { _, isEnabled in
                    VintageMacIcon.setEnabled(isEnabled)
                }
            }
        }
        .navigationTitle(String(localized: "Appearance"))
    }

    private var providerOrderRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.registeredProvidersOrdered.enumerated()), id: \.element.id) { index, provider in
                providerOrderRow(provider, at: index)

                if index < viewModel.registeredProvidersOrdered.count - 1 {
                    Divider()
                        .padding(.leading, 33)
                }
            }
        }
    }

    private func providerOrderRow(_ provider: ProviderInfo, at index: Int) -> some View {
        HStack(spacing: 10) {
            ProviderLogoBadge(glyph: provider.glyph)
            Text(provider.displayName)
                .lineLimit(2)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help(String(localized: "Drag to reorder providers"))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onDrag {
            draggedProviderId = provider.id
            return NSItemProvider(object: provider.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: ProviderOrderDropDelegate(
                destinationId: provider.id,
                providers: viewModel.registeredProvidersOrdered,
                draggedProviderId: $draggedProviderId,
                move: viewModel.moveProvider
            )
        )
        .accessibilityAction(named: String(localized: "Move up")) {
            moveProvider(at: index, direction: -1)
        }
        .accessibilityAction(named: String(localized: "Move down")) {
            moveProvider(at: index, direction: 1)
        }
    }

    private func moveProvider(at index: Int, direction: Int) {
        let destinationIndex = index + direction
        guard viewModel.registeredProvidersOrdered.indices.contains(destinationIndex) else { return }
        let destination = direction < 0 ? destinationIndex : destinationIndex + 1
        viewModel.moveProvider(from: IndexSet(integer: index), to: destination)
    }

    private var vintageMacSubtitle: String {
        String(
            localized: "Show a classic Happy / Sad Mac face instead of the ring in the menu bar"
        )
    }
}

private struct ProviderOrderDropDelegate: DropDelegate {
    let destinationId: String
    let providers: [ProviderInfo]
    @Binding var draggedProviderId: String?
    let move: (IndexSet, Int) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggedProviderId,
              draggedProviderId != destinationId,
              let sourceIndex = providers.firstIndex(where: { $0.id == draggedProviderId }),
              let destinationIndex = providers.firstIndex(where: { $0.id == destinationId })
        else {
            return
        }

        let destination = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        move(IndexSet(integer: sourceIndex), destination)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedProviderId = nil
        return true
    }
}

@MainActor
private struct BalanceThresholdsSettingsRow: View {
    @State private var lowInput: Double = BalanceThresholds.low
    @State private var okInput: Double = BalanceThresholds.ok
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            lowStepper
            okStepper
            tierPreview
            hint
        }
        .padding(.vertical, 4)
    }

    private var lowStepper: some View {
        stepperRow(
            label: String(localized: "Low below"),
            value: $lowInput,
            range: 0 ... 1000
        )
        .onChange(of: lowInput) { _, newLow in
            if okInput <= newLow {
                okInput = newLow + 1
            }
            persist()
        }
    }

    private var okStepper: some View {
        stepperRow(
            label: String(localized: "OK above"),
            value: $okInput,
            range: (lowInput + 1) ... 1000
        )
        .onChange(of: okInput) { _, _ in
            persist()
        }
    }

    private func stepperRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        Stepper(value: value, in: range, step: 1) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue, format: .number)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }

    private var tierPreview: some View {
        let lowInt = Int(lowInput)
        let okInt = Int(okInput)
        return VStack(alignment: .leading, spacing: 4) {
            swatchRow(
                color: ProviderVisualStyle.tierColor(.critical, scheme: colorScheme),
                caption: String(localized: "under \(lowInt)")
            )
            swatchRow(
                color: ProviderVisualStyle.tierColor(.warn, scheme: colorScheme),
                caption: String(localized: "\(lowInt)–\(okInt)")
            )
            swatchRow(
                color: ProviderVisualStyle.tierColor(.good, scheme: colorScheme),
                caption: String(localized: "\(okInt) and up")
            )
        }
        .padding(.top, 2)
    }

    private func swatchRow(color: Color, caption: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var hint: some View {
        Text(String(localized: "Applies to every provider currency (USD, CNY, …)."))
            .font(.caption2)
            .foregroundColor(.secondary)
    }

    private func persist() {
        BalanceThresholds.set(low: lowInput, ok: okInput)
    }
}
