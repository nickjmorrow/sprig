import SprigCore
import SwiftUI

/// "Archived · Undo", shown for a few seconds under the list after any story is archived,
/// including one archived because it was read to the end.
struct UndoArchiveBar: View {
    @EnvironmentObject private var engine: SyncEngine

    var body: some View {
        ZStack {
            if let archived = engine.lastArchived {
                bar(archived)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: archived.id) {
                        // Only a timer that ran out hides it; a copy of the bar leaving the screen
                        // (another tab, a pushed reader) cancels its task and must not.
                        do {
                            try await Task.sleep(for: .seconds(8))
                            engine.dismissUndo(archived)
                        } catch {}
                    }
            }
        }
        .animation(.snappy(duration: 0.25), value: engine.lastArchived)
    }

    private func bar(_ archived: ArchivedStory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Archived")
                    .font(.subheadline.weight(.semibold))
                Text(archived.item.displayTitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { engine.undoArchive() } label: {
                Text("Undo").padding(.vertical, 8).padding(.horizontal, 6).contentShape(Rectangle())
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .tint(Theme.accent)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {} // The bar itself swallows taps, so none reach the row underneath.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line.opacity(0.5)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
