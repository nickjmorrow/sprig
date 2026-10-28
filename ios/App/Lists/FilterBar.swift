import BouquetCore
import SwiftUI

/// The time picker and the topic chips above every list.
struct FilterBar: View {
    @Binding var filter: ItemFilter
    let topics: [String]
    var showsFavorites = false

    var body: some View {
        VStack(spacing: 10) {
            timePicker
            chips
        }
        .padding(.vertical, 8)
        .background(Theme.bg)
    }

    private var timePicker: some View {
        HStack(spacing: 2) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                let isOn = filter.range == range
                Button {
                    withAnimation(.snappy(duration: 0.2)) { filter.range = range }
                } label: {
                    Text(range.label)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Theme.bg : Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.control))
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: filter.range)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if showsFavorites {
                    chip("★ Favorites", isOn: filter.favoritesOnly) { filter.favoritesOnly.toggle() }
                }
                chip("All", isOn: filter.topic == nil) { filter.topic = nil }
                ForEach(topics, id: \.self) { topic in
                    chip(topic, isOn: filter.topic == topic) {
                        filter.topic = filter.topic == topic ? nil : topic
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Theme.bg : Theme.text.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? Theme.text : Theme.control))
        }
        .buttonStyle(.plain)
    }
}
