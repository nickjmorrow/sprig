import BouquetCore
import Foundation

/// The reader's HTML and scroll-progress script, shared by the iPhone and Mac web views.
enum ArticlePage {
    static let fontSizes = [17, 19, 21]

    /// Posts how far down the page you are (0...1) to the `progress` message handler, at most every 250 ms.
    static let progressScript = """
    let pending = false;
    addEventListener('scroll', () => {
      if (pending) return;
      pending = true;
      setTimeout(() => {
        pending = false;
        const room = document.documentElement.scrollHeight - innerHeight;
        webkit.messageHandlers.progress.postMessage(room > 0 ? Math.max(0, Math.min(1, scrollY / room)) : 1);
      }, 250);
    }, { passive: true });
    """

    static func html(for item: Item, fontSize: Int, extraCSS: String = "") -> String {
        let stylesheet = Bundle.main.url(forResource: "reader", withExtension: "css")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let kicker = ([item.displaySite] + item.topics.prefix(1)).map(escape).joined(separator: " · ")
        let title = item.kind == .tweet ? "" : "<h1 class=\"title\">\(escape(item.displayTitle))</h1>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(stylesheet) :root { --size: \(fontSize)px; } \(extraCSS)</style></head>
        <body><div class="kicker">\(kicker) · <b>\(item.minutes) min</b></div>\(title)\(item.contentHtml)</body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
