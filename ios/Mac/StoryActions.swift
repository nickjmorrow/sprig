import SprigCore
import SwiftUI

typealias Action = @MainActor () -> Void

/// What the Story menu can do to the selected story. Nil actions are greyed out.
struct StoryActions {
    let item: Item
    let archive: Action?
    let moveToInbox: Action?
    let toggleStar: Action
    let markUnread: Action
    let openOriginal: Action
    let copyLink: Action
    let next: Action
    let previous: Action
}

private struct StoryActionsKey: FocusedValueKey {
    typealias Value = StoryActions
}

extension FocusedValues {
    var storyActions: StoryActions? {
        get { self[StoryActionsKey.self] }
        set { self[StoryActionsKey.self] = newValue }
    }
}

/// The Story menu and its single-key shortcuts. They only apply while the main window is key and a
/// story is selected, so typing in Settings or the topics sheet never triggers them.
struct StoryCommands: Commands {
    @FocusedValue(\.storyActions) private var actions
    @AppStorage("reader.fontStep") private var fontStep = 0

    var body: some Commands {
        CommandMenu("Story") {
            Button("Next Story") { actions?.next() }
                .keyboardShortcut("j", modifiers: [])
                .disabled(actions == nil)
            Button("Previous Story") { actions?.previous() }
                .keyboardShortcut("k", modifiers: [])
                .disabled(actions == nil)
            Divider()
            Button("Archive") { actions?.archive?() }
                .keyboardShortcut("e", modifiers: [])
                .disabled(actions?.archive == nil)
            Button(actions?.item.location == .feed ? "Keep in Inbox" : "Move to Inbox") { actions?.moveToInbox?() }
                .keyboardShortcut("i", modifiers: [])
                .disabled(actions?.moveToInbox == nil)
            Button(actions?.item.favorite == true ? "Unstar" : "Star") { actions?.toggleStar() }
                .keyboardShortcut("s", modifiers: [])
                .disabled(actions == nil)
            Button("Mark as Unread") { actions?.markUnread() }
                .keyboardShortcut("u", modifiers: [])
                .disabled(actions == nil)
            Button("Open Original") { actions?.openOriginal() }
                .keyboardShortcut("o", modifiers: [])
                .disabled(actions == nil)
            Button("Copy Link") { actions?.copyLink() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Divider()
            Button("Bigger Text") { fontStep = min(fontStep + 1, ArticlePage.fontSizes.count - 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { fontStep = max(fontStep - 1, 0) }
                .keyboardShortcut("-", modifiers: .command)
        }
    }
}
