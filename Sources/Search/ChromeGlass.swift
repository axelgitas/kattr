import SwiftUI
import AppKit

/// Discrete glass strength presets mapping to supported macOS NSVisualEffectView materials.
enum ChromeGlassStrength: String, CaseIterable, Identifiable {
    case subtle
    case regular
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: return "Subtle"
        case .regular: return "Regular"
        case .strong: return "Strong"
        }
    }

    /// Resolves the authentic AppKit NSVisualEffectView material for the container.
    /// .regular reproduces Search's default production appearance (.sidebar for sidebar, .headerView for top strip).
    func material(isSidebar: Bool) -> NSVisualEffectView.Material {
        switch self {
        case .subtle:
            return isSidebar ? .headerView : .titlebar
        case .regular:
            return isSidebar ? .sidebar : .headerView
        case .strong:
            return .underWindowBackground
        }
    }
}

/// Manages persistence, live change notifications, and resolution for Chrome FrostedGlass settings.
@MainActor
final class ChromeGlassSettings: ObservableObject {
    static let shared = ChromeGlassSettings()

    static let didChange = Notification.Name("SearchChromeGlassDidChange")
    static let tintKey = "appearance.chrome.tintOpacity"
    static let strengthKey = "appearance.chrome.glassStrength"
    static let foundationOpacityKey = "appearance.chrome.artworkFoundationOpacity"

    static let defaultTint: Double = 0.35
    static let defaultStrength: ChromeGlassStrength = .regular
    static let defaultArtworkFoundationOpacity: Double = 0.90

    /// Safe range for the tint overlay slider.
    static let tintRange: ClosedRange<Double> = 0.10...1.00
    static let tintStep: Double = 0.05

    private init() {}

    /// Effective tint opacity layered over FrostedGlass.
    var tintOpacity: Double {
        get {
            if let val = Store.settings.object(forKey: Self.tintKey) as? Double {
                return min(max(val, Self.tintRange.lowerBound), Self.tintRange.upperBound)
            }
            return Self.defaultTint
        }
        set {
            let clamped = min(max(newValue, Self.tintRange.lowerBound), Self.tintRange.upperBound)
            Store.settings.set(clamped, forKey: Self.tintKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Discrete glass material preset.
    var strength: ChromeGlassStrength {
        get {
            if let raw = Store.settings.string(forKey: Self.strengthKey),
               let preset = ChromeGlassStrength(rawValue: raw) {
                return preset
            }
            return Self.defaultStrength
        }
        set {
            Store.settings.set(newValue.rawValue, forKey: Self.strengthKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// High-density foundation opacity underneath artwork layers, anchoring the atmospheric fade.
    var artworkFoundationOpacity: Double {
        get {
            if let val = Store.settings.object(forKey: Self.foundationOpacityKey) as? Double {
                return min(max(val, 0.0), 1.0)
            }
            return Self.defaultArtworkFoundationOpacity
        }
        set {
            let clamped = min(max(newValue, 0.0), 1.0)
            Store.settings.set(clamped, forKey: Self.foundationOpacityKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Whether any glass setting differs from the default.
    var isCustomized: Bool {
        Store.settings.object(forKey: Self.tintKey) != nil ||
        Store.settings.object(forKey: Self.strengthKey) != nil ||
        Store.settings.object(forKey: Self.foundationOpacityKey) != nil
    }

    /// Resolves the NSVisualEffectView material for the given container based on the active strength.
    func material(isSidebar: Bool) -> NSVisualEffectView.Material {
        strength.material(isSidebar: isSidebar)
    }

    /// Resets all chrome glass settings to default and notifies observers.
    func reset() {
        Store.settings.removeObject(forKey: Self.tintKey)
        Store.settings.removeObject(forKey: Self.strengthKey)
        Store.settings.removeObject(forKey: Self.foundationOpacityKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

