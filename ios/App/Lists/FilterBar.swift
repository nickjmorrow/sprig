import SprigCore
import SwiftUI

/// The time control and the topic chips above every list.
struct FilterBar: View {
    @Binding var filter: ItemFilter
    let topics: [String]
    var showsFavorites = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Reading time", selection: $filter.range) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .sensoryFeedback(.selection, trigger: filter.range)
            chips
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if showsFavorites {
                    chip("Favorites", systemImage: "star.fill", isOn: filter.favoritesOnly) { filter.favoritesOnly.toggle() }
                }
                chip("All topics", isOn: filter.topic == nil) { filter.topic = nil }
                ForEach(topics, id: \.self) { topic in
                    chip(topic, isOn: filter.topic == topic) {
                        filter.topic = filter.topic == topic ? nil : topic
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, systemImage: String? = nil, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? Theme.onAccent : Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(Capsule().fill(isOn ? Theme.accent : Theme.control))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
