import SprigCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share → Sprig: sends the link to the server, or queues it for the app to send when it can.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await save() }
    }

    private func save() async {
        guard let url = await sharedURL() else {
            model.state = .noLink
            return finish(after: .seconds(1.5))
        }
        // Queue first so nothing is lost if iOS ends the extension mid-request; the server
        // dedupes by link, so a queued copy that also got through does no harm.
        let store = try? LocalStore.shared()
        let queued = try? store?.enqueueShare(url: url)
        do {
            _ = try await APIClient(settings: ServerSettings.load()).createItem(url: url, timeout: 5)
            if let queued { try? store?.removeShare(queued) }
            model.state = .saved
        } catch {
            // Offline, off Tailscale or not set up yet: the app sends it on its next sync.
            model.state = queued == nil ? .failed : .queued
        }
        finish(after: .seconds(model.state == .failed ? 2.5 : 1))
    }

    private func finish(after delay: Duration) {
        Task {
            try? await Task.sleep(for: delay)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func sharedURL() async -> URL? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = firstLink(in: text) {
                return url
            }
        }
        return nil
    }

    private func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range).compactMap(\.url).first { $0.scheme?.hasPrefix("http") == true }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State { case saving, saved, queued, noLink, failed }
    @Published var state = State.saving
}

struct ShareCard: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        VStack(spacing: 12) {
            icon.font(.system(size: 34, weight: .semibold))
            Text(message)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
        }
        .frame(width: 230, height: 150)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.25))
        .animation(.snappy, value: model.state)
        .sensoryFeedback(.success, trigger: model.state) { _, new in new == .saved || new == .queued }
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .saving: ProgressView().controlSize(.large).tint(Theme.dim)
        case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .queued: Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(Theme.accent)
        case .noLink: Image(systemName: "link.badge.plus").foregroundStyle(Theme.dim)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
        }
    }

    private var message: String {
        switch model.state {
        case .saving: "Saving…"
        case .saved: "Saved to Sprig"
        case .queued: "Saved, will send\nwhen online"
        case .noLink: "No link to save"
        case .failed: "Couldn't save.\nOpen Sprig and try again."
        }
    }
}
