#if os(iOS)
import SwiftUI
import UIKit

/// Where a `SYSRemoteImage` is: still loading, loaded, or failed (offline says whether the cause was no connection).
public enum SYSImagePhase {
    case loading
    case success(UIImage)
    case failed(offline: Bool)

    public var image: UIImage? {
        if case .success(let image) = self { return image }
        return nil
    }
}

/// A picture from a web address or a file, kept on the device by `SYSImageStore`.
///
/// It shows a kept picture straight away, also offline, and tries again by itself when the connection comes back
/// or the app returns to the foreground after a failed load. The `content` closure draws each phase.
public struct SYSRemoteImage<Content: View>: View {
    private struct Settled {
        let url: URL
        let side: CGFloat
        let phase: SYSImagePhase
    }

    private struct Trigger: Hashable {
        let url: URL?
        let side: CGFloat
        let online: Bool
        let retry: Int
    }

    private let url: URL?
    private let side: CGFloat
    private let onLoad: ((UIImage) -> Void)?
    private let content: (SYSImagePhase) -> Content

    @ObservedObject private var connectivity = SYSConnectivity.shared
    @State private var settled: Settled?
    @State private var retry = 0

    public init(
        url: URL?,
        maxPixelSize: CGFloat = 512,
        onLoad: ((UIImage) -> Void)? = nil,
        @ViewBuilder content: @escaping (SYSImagePhase) -> Content
    ) {
        self.url = url
        self.side = SYSImageStore.bucket(maxPixelSize)
        self.onLoad = onLoad
        self.content = content
    }

    private var phase: SYSImagePhase {
        guard let url else { return .loading }
        if let settled, settled.url == url, settled.side == side { return settled.phase }
        if let hit = SYSImageStore.cachedImage(for: url, maxPixelSize: side) { return .success(hit) }
        return .loading
    }

    public var body: some View {
        let current = phase
        content(current)
            .animation(.easeOut(duration: 0.25), value: current.image != nil)
            .task(id: Trigger(url: url, side: side, online: connectivity.isOnline, retry: retry)) {
                await load()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if case .failed = phase { retry += 1 }
            }
    }

    private func load() async {
        guard let url else { return }
        if let settled, settled.url == url, settled.side == side, settled.phase.image != nil { return }
        do {
            let image = try await SYSImageStore.shared.image(for: url, maxPixelSize: side)
            if Task.isCancelled { return }
            settled = Settled(url: url, side: side, phase: .success(image))
            onLoad?(image)
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            let offline = (error as? SYSImageError) == .offline
            settled = Settled(url: url, side: side, phase: .failed(offline: offline))
        }
    }
}

/// The usual drawing for `SYSRemoteImage`: the loaded picture through one closure, anything else through another.
public struct SYSImageContent<Loaded: View, Placeholder: View>: View {
    let phase: SYSImagePhase
    let loaded: (Image) -> Loaded
    let placeholder: () -> Placeholder

    public var body: some View {
        if let image = phase.image {
            loaded(Image(uiImage: image))
        } else {
            placeholder()
        }
    }
}

public extension SYSRemoteImage {
    init<Loaded: View, Placeholder: View>(
        url: URL?,
        maxPixelSize: CGFloat = 512,
        onLoad: ((UIImage) -> Void)? = nil,
        @ViewBuilder content loaded: @escaping (Image) -> Loaded,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where Content == SYSImageContent<Loaded, Placeholder> {
        self.init(url: url, maxPixelSize: maxPixelSize, onLoad: onLoad) { phase in
            SYSImageContent(phase: phase, loaded: loaded, placeholder: placeholder)
        }
    }
}
#endif
