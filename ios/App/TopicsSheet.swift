import BouquetCore
import SwiftUI

/// Pick 1–3 topics for an item. Your picks also teach the tagger.
struct TopicsSheet: View {
    let item: Item
    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []

    private static let maxTopics = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                FlowLayout(spacing: 8) {
                    ForEach(((try? engine.store.topics()) ?? []) + ["Other"], id: \.self) { topic in
                        let isOn = selected.contains(topic)
                        Button {
                            toggle(topic)
                        } label: {
                            Text(topic)
                                .font(.system(size: 15, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? Theme.bg : Theme.text)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(isOn ? Theme.accent : Theme.control))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                Text("Pick up to \(Self.maxTopics).")
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
            .background(Theme.bg)
            .navigationTitle("Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        engine.update(item, PatchChanges(topics: selected))
                        dismiss()
                    }
                    .disabled(selected.isEmpty || selected == item.topics)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { selected = item.topics }
    }

    private func toggle(_ topic: String) {
        if let index = selected.firstIndex(of: topic) {
            selected.remove(at: index)
        } else if selected.count < Self.maxTopics {
            selected.append(topic)
        }
    }
}

/// Lays chips out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row(y: 0)]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
