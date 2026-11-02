/// Which story to select once the selected one has left the list (archived, moved): the next one
/// down that's still there, else the nearest one above, else nothing.
public func nextSelection(after removed: String, old: [String], new: [String]) -> String? {
    if new.contains(removed) { return removed }
    guard let index = old.firstIndex(of: removed) else { return nil }
    let remaining = Set(new)
    return old[(index + 1)...].first(where: remaining.contains)
        ?? old[..<index].last(where: remaining.contains)
}
