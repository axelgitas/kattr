import SwiftUI

/// Centralized management and persistence for independent artwork appearance opacity settings,
/// controlling image-derived artwork and atmospheric blur layers across New Tab and Chrome independently.
@MainActor
final class AppearanceTransparencySettings: ObservableObject {
    static let shared = AppearanceTransparencySettings()

    static let didChange = Notification.Name("SearchAppearanceTransparencyDidChange")

    static let newTabArtworkOpacityKey = "appearance.newTabArtworkOpacity"
    static let chromeArtworkOpacityKey = "appearance.chromeArtworkOpacity"

    static let defaultArtworkOpacity: Double = 1.0

    static let range: ClosedRange<Double> = 0.0...1.0
    static let step: Double = 0.05

    private init() {}

    /// New Tab artwork and atmosphere opacity (0.0 = completely invisible, 1.0 = fully visible).
    var newTabArtworkOpacity: Double {
        get {
            if let val = Store.settings.object(forKey: Self.newTabArtworkOpacityKey) as? Double {
                return min(max(val, Self.range.lowerBound), Self.range.upperBound)
            }
            return Self.defaultArtworkOpacity
        }
        set {
            let clamped = min(max(newValue, Self.range.lowerBound), Self.range.upperBound)
            Store.settings.set(clamped, forKey: Self.newTabArtworkOpacityKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Chrome continuous artwork and atmosphere opacity (0.0 = completely invisible, 1.0 = fully visible).
    var chromeArtworkOpacity: Double {
        get {
            if let val = Store.settings.object(forKey: Self.chromeArtworkOpacityKey) as? Double {
                return min(max(val, Self.range.lowerBound), Self.range.upperBound)
            }
            return Self.defaultArtworkOpacity
        }
        set {
            let clamped = min(max(newValue, Self.range.lowerBound), Self.range.upperBound)
            Store.settings.set(clamped, forKey: Self.chromeArtworkOpacityKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Whether New Tab artwork opacity differs from default (1.0).
    var isNewTabArtworkCustomized: Bool {
        if Store.settings.object(forKey: Self.newTabArtworkOpacityKey) != nil {
            return abs(newTabArtworkOpacity - Self.defaultArtworkOpacity) > 0.001
        }
        return false
    }

    /// Whether Chrome artwork opacity differs from default (1.0).
    var isChromeArtworkCustomized: Bool {
        if Store.settings.object(forKey: Self.chromeArtworkOpacityKey) != nil {
            return abs(chromeArtworkOpacity - Self.defaultArtworkOpacity) > 0.001
        }
        return false
    }

    /// Resets New Tab artwork opacity to default (1.0).
    func resetNewTabArtwork() {
        Store.settings.removeObject(forKey: Self.newTabArtworkOpacityKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Resets Chrome artwork opacity to default (1.0).
    func resetChromeArtwork() {
        Store.settings.removeObject(forKey: Self.chromeArtworkOpacityKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
