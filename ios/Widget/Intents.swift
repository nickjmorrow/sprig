import AppIntents
import SprigCore
import Foundation
import WidgetKit

/// The widget's check button: archives the item, the same as Archive in the app.
struct MarkDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark as done"
    static let isDiscoverable = false

    @Parameter(title: "Item") var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        let store = try LocalStore.shared()
        try store.change(itemID, PatchChanges(location: .archive))
        WidgetCenter.shared.reloadAllTimelines()
        // As in the share extension: send it now if the server answers quickly, otherwise the
        // app sends it on its next sync.
        let api = APIClient(settings: ServerSettings.load())
        for patch in try store.pendingPatches() where patch.itemId == itemID {
            guard (try? await api.patch(id: patch.itemId, changes: patch.changes, at: patch.at, timeout: 5)) != nil else { break }
            try store.removePatch(patch)
        }
        return .result()
    }
}
