import Core
import SwiftUI

enum ProviderSettingsOrder {
    /// Moves within the visible providers only. Hidden providers keep their
    /// saved slots, so turning one back on restores its old position.
    static func reordered(
        all: [String],
        visible: [String],
        from source: IndexSet,
        to destination: Int
    ) -> [String] {
        var moved = visible
        moved.move(fromOffsets: source, toOffset: destination)
        let visibleIds = Set(visible)
        var nextVisible = moved.makeIterator()
        return all.map { id in
            guard visibleIds.contains(id) else { return id }
            return nextVisible.next() ?? id
        }
    }
}

@MainActor
struct ProviderSettingsList: View {
    let viewModel: QuotaViewModel
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(Array(tracking.enumerated()), id: \.element.id) { index, provider in
                        row(provider)
                            .accessibilityAction(named: String(displayLocalized: "Move up", bundle: .module)) {
                                move(from: index, to: index - 1)
                            }
                            .accessibilityAction(named: String(displayLocalized: "Move down", bundle: .module)) {
                                move(from: index, to: index + 2)
                            }
                    }
                    .onMove { source, destination in
                        persistMove(from: source, to: destination)
                    }
                } header: {
                    Text(String(displayLocalized: "Tracking", bundle: .module))
                }

                if !notTracking.isEmpty {
                    Section {
                        ForEach(notTracking) { provider in
                            row(provider)
                        }
                    } header: {
                        Text(String(displayLocalized: "Not tracking", bundle: .module))
                    }
                }
            }
            .listStyle(.sidebar)

            if tracking.count > 1 {
                SettingsCaption(String(displayLocalized: "Drag to reorder.", bundle: .module))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
    }

    private var tracking: [ProviderInfo] {
        viewModel.registeredProvidersOrdered.filter { viewModel.isEnabled($0.id) }
    }

    private var notTracking: [ProviderInfo] {
        viewModel.registeredProvidersOrdered.filter { !viewModel.isEnabled($0.id) }
    }

    private func row(_ provider: ProviderInfo) -> some View {
        let status = ProviderStatusPresentation(
            state: viewModel.providerStates[provider.id],
            isEnabled: viewModel.isEnabled(provider.id)
        )
        return HStack(spacing: 8) {
            ProviderLogoBadge(glyph: provider.glyph)
            Text(provider.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if status != .off {
                ProviderStatusMark(status: status)
            }
        }
        .tag(Optional(provider.id))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String.localizedStringWithFormat(
            String(displayLocalized: "Provider list row accessibility label", bundle: .module),
            provider.displayName,
            status.label
        ))
    }

    private func move(from index: Int, to destination: Int) {
        guard tracking.indices.contains(index),
              (0 ... tracking.count).contains(destination),
              destination != index, destination != index + 1
        else {
            return
        }
        persistMove(from: IndexSet(integer: index), to: destination)
    }

    private func persistMove(from source: IndexSet, to destination: Int) {
        viewModel.persistOrder(ProviderSettingsOrder.reordered(
            all: viewModel.registeredProvidersOrdered.map(\.id),
            visible: tracking.map(\.id),
            from: source,
            to: destination
        ))
    }
}
