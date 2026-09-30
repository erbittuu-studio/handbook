import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

public enum SYSAppStore {
    public static let infoKey = "SYSAppStoreID"

    public static func id(bundle: Bundle = .main) -> String? {
        bundle.object(forInfoDictionaryKey: infoKey) as? String
    }

    public static func url(id: String) -> URL? {
        URL(string: "https://apps.apple.com/app/id\(id)")
    }

    public static func reviewURL(id: String) -> URL? {
        URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }

    public static func url(bundle: Bundle = .main) -> URL? {
        id(bundle: bundle).flatMap { url(id: $0) }
    }

    #if canImport(UIKit) && !os(watchOS)
    @MainActor
    public static func openReview(bundle: Bundle = .main) {
        guard let id = id(bundle: bundle), let url = reviewURL(id: id) else { return }
        UIApplication.shared.open(url)
    }
    #endif
}
