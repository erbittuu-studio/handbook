import Foundation

/// One web link of the app, as the served config describes it.
public struct SYSLink: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let url: URL
}

struct SYSLinkEntry: Codable, Equatable, Sendable {
    var id: String
    var title: SYSLocalizedText?
    var symbol: String?
    var url: String
    var enabled: Bool?

    private static let symbols = [
        "support": "lifepreserver.fill",
        "privacy": "hand.raised.fill",
        "terms": "doc.text.fill",
        "website": "globe"
    ]

    static func symbol(for id: String) -> String? { symbols[id] }

    /// The four standard links when the config has no `links` list: an address in `urls` wins; otherwise the app works it out
    /// from the website address and its own id (`<site>/apps/<id>/support`). With neither, that link is left out.
    static func standard(urls: [String: String]?, contentID: String?) -> [SYSLinkEntry] {
        let site = urls?["website"].flatMap(URL.init(string:)).flatMap { origin(of: $0) }
        return ["support", "privacy", "terms", "website"].compactMap { id in
            if let written = urls?[id] { return SYSLinkEntry(id: id, title: nil, symbol: nil, url: written, enabled: nil) }
            guard id != "website", let site, let contentID else { return nil }
            return SYSLinkEntry(id: id, title: nil, symbol: nil, url: "\(site)/apps/\(contentID)/\(id)", enabled: nil)
        }
    }

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return "\(scheme)://\(host)"
    }
}

extension SYSConfig {
    /// The links to show, in the order the config lists them. A config with no `links` list gets the four standard links
    /// (support, privacy, terms, website). Only https addresses are kept, so a wrong config can never open another kind of link.
    func links(for languages: [String] = Locale.preferredLanguages) -> [SYSLink] {
        let snapshot = data
        let entries = snapshot.links ?? SYSLinkEntry.standard(urls: snapshot.urls, contentID: contentID)
        let text = SYSLinksText.forLanguages(languages)
        return entries.compactMap { entry in
            guard entry.enabled != false, let url = resolvedURL(entry.url), url.scheme == "https" else { return nil }
            let written = entry.title?.text(for: languages) ?? ""
            let title = written.isEmpty ? (text.title(forLink: entry.id) ?? entry.id.capitalized) : written
            return SYSLink(id: entry.id, title: title, symbol: entry.symbol ?? SYSLinkEntry.symbol(for: entry.id) ?? "link", url: url)
        }
    }

    func linksTitle(for languages: [String] = Locale.preferredLanguages) -> String {
        let written = data.linksTitle?.text(for: languages) ?? ""
        return written.isEmpty ? SYSLinksText.forLanguages(languages).about : written
    }
}
