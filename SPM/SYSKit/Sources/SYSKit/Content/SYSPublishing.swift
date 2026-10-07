/// Something a manifest can mark as not live yet.
public protocol SYSPublishable {
    var isPublished: Bool { get }
}

/// Previewing draft content without a second server.
public enum SYSPublishing {
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    public static func visible<T: SYSPublishable>(_ items: [T]) -> [T] {
        visible(items, includeUnpublished: isDebugBuild)
    }

    static func visible<T: SYSPublishable>(_ items: [T], includeUnpublished: Bool) -> [T] {
        includeUnpublished ? items : items.filter(\.isPublished)
    }
}
