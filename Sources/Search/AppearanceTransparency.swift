import SwiftUI

/// Centralized management and persistence for global appearance transparency settings,
/// controlling base foundations and image-derived artwork layers across both Chrome and New Tab.
@MainActor
final class AppearanceTransparencySettings: ObservableObject {
    static let shared = AppearanceTransparencySettings()

    static let didChange = Notification.Name("SearchAppearanceTransparencyDidChange")

    static let backgroundTransparencyKey = "appearance.backgroundTransparency"
    static let artworkTransparencyKey = "appearance.artworkTransparency"

    static let defaultBackgroundTransparency: Double = 0.0
    static let defaultArtworkTransparency: Double = 0.0

    static let range: ClosedRange<Double> = 0.0...1.0
    static let step: Double = 0.05

    private init() {
        NotificationCenter.default.addObserver(
            forName: BrowserSurfaceSettings.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Background / surface transparency (delegates to BrowserSurfaceSettings).
    var backgroundTransparency: Double {
        get { BrowserSurfaceSettings.shared.surfaceTransparency }
        set { BrowserSurfaceSettings.shared.surfaceTransparency = newValue }
    }

    /// Artwork & atmosphere transparency (0.0 = full normal artwork appearance, 1.0 = completely transparent artwork).
    var artworkTransparency: Double {
        get {
            if let val = Store.settings.object(forKey: Self.artworkTransparencyKey) as? Double {
                return min(max(val, Self.range.lowerBound), Self.range.upperBound)
            }
            return Self.defaultArtworkTransparency
        }
        set {
            let clamped = min(max(newValue, Self.range.lowerBound), Self.range.upperBound)
            Store.settings.set(clamped, forKey: Self.artworkTransparencyKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Resolved opacity of surface/canvas layers (1.0 = opaque, 0.0 = clear).
    var backgroundOpacity: Double {
        BrowserSurfaceSettings.shared.surfaceOpacity
    }

    /// Resolved opacity of image-derived artwork and atmospheric blur layers (1.0 = full strength, 0.0 = clear).
    var artworkOpacity: Double {
        max(0.0, min(1.0, 1.0 - artworkTransparency))
    }

    /// Whether background transparency differs from default.
    var isBackgroundCustomized: Bool {
        BrowserSurfaceSettings.shared.isTransparencyCustomized
    }

    /// Whether artwork transparency differs from default.
    var isArtworkCustomized: Bool {
        Store.settings.object(forKey: Self.artworkTransparencyKey) != nil && artworkTransparency > 0.001
    }

    /// Whether any transparency setting is customized from its default.
    var isCustomized: Bool {
        isBackgroundCustomized || isArtworkCustomized
    }

    /// Resets background transparency to default.
    func resetBackground() {
        BrowserSurfaceSettings.shared.resetTransparency()
    }

    /// Resets artwork transparency to default.
    func resetArtwork() {
        Store.settings.removeObject(forKey: Self.artworkTransparencyKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Resets all transparency settings to default.
    func reset() {
        BrowserSurfaceSettings.shared.resetTransparency()
        resetArtwork()
    }
}

