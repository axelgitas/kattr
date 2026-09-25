import SwiftUI
import AppKit

/// Discrete blur strength presets mapping to supported macOS NSVisualEffectView materials.
enum BlurStrength: String, CaseIterable, Identifiable {
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

typealias ChromeGlassStrength = BlurStrength

/// Manages persistence, live change notifications, and resolution for global BrowserSurface settings.
@MainActor
final class BrowserSurfaceSettings: ObservableObject {
    static let shared = BrowserSurfaceSettings()

    static let didChange = Notification.Name("SearchBrowserSurfaceDidChange")

    static let surfaceTransparencyKey = "appearance.surfaceTransparency"
    static let legacyBackgroundTransparencyKey = "appearance.backgroundTransparency"

    static let blurStrengthKey = "appearance.blurStrength"
    static let legacyStrengthKey = "appearance.chrome.glassStrength"

    static let foundationOpacityKey = "appearance.chrome.artworkFoundationOpacity"

    static let defaultTransparency: Double = 0.0
    static let defaultBlurStrength: BlurStrength = .regular
    static let defaultArtworkFoundationOpacity: Double = 0.90

    static let transparencyRange: ClosedRange<Double> = 0.0...1.0
    static let transparencyStep: Double = 0.05

    /// Forwarders for backwards compatibility during migration
    static var tintRange: ClosedRange<Double> { AppearanceGlassSettings.tintRange }
    static var tintStep: Double { AppearanceGlassSettings.tintStep }
    static var defaultTint: Double { AppearanceGlassSettings.defaultTint }

    private init() {}

    /// Global surface transparency (0.0 = fully present, 1.0 = maximally transparent).
    var surfaceTransparency: Double {
        get {
            if let val = Store.settings.object(forKey: Self.surfaceTransparencyKey) as? Double {
                return min(max(val, Self.transparencyRange.lowerBound), Self.transparencyRange.upperBound)
            }
            if let val = Store.settings.object(forKey: Self.legacyBackgroundTransparencyKey) as? Double {
                return min(max(val, Self.transparencyRange.lowerBound), Self.transparencyRange.upperBound)
            }
            return Self.defaultTransparency
        }
        set {
            let clamped = min(max(newValue, Self.transparencyRange.lowerBound), Self.transparencyRange.upperBound)
            Store.settings.set(clamped, forKey: Self.surfaceTransparencyKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Effective opacity of the complete BrowserSurface (1.0 = fully present, 0.0 = completely transparent).
    var surfaceOpacity: Double {
        max(0.0, min(1.0, 1.0 - surfaceTransparency))
    }

    /// Discrete blur strength preset.
    var blurStrength: BlurStrength {
        get {
            if let raw = Store.settings.string(forKey: Self.blurStrengthKey),
               let preset = BlurStrength(rawValue: raw) {
                return preset
            }
            if let raw = Store.settings.string(forKey: Self.legacyStrengthKey),
               let preset = BlurStrength(rawValue: raw) {
                return preset
            }
            return Self.defaultBlurStrength
        }
        set {
            Store.settings.set(newValue.rawValue, forKey: Self.blurStrengthKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Compatibility forwarder for strength
    var strength: BlurStrength {
        get { blurStrength }
        set { blurStrength = newValue }
    }

    /// Effective tint opacity layered over FrostedGlass (delegates to global AppearanceGlassSettings).
    var tintOpacity: Double {
        get { AppearanceGlassSettings.shared.tintOpacity }
        set { AppearanceGlassSettings.shared.tintOpacity = newValue }
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

    /// Whether surface transparency differs from the default.
    var isTransparencyCustomized: Bool {
        if Store.settings.object(forKey: Self.surfaceTransparencyKey) != nil {
            return surfaceTransparency > 0.001
        }
        if Store.settings.object(forKey: Self.legacyBackgroundTransparencyKey) != nil {
            return surfaceTransparency > 0.001
        }
        return false
    }

    /// Whether blur strength differs from the default.
    var isBlurStrengthCustomized: Bool {
        if Store.settings.object(forKey: Self.blurStrengthKey) != nil {
            return blurStrength != Self.defaultBlurStrength
        }
        if Store.settings.object(forKey: Self.legacyStrengthKey) != nil {
            return blurStrength != Self.defaultBlurStrength
        }
        return false
    }

    var isCustomized: Bool {
        isBlurStrengthCustomized
    }

    /// Resolves the NSVisualEffectView material for the given container based on the active strength.
    func material(isSidebar: Bool) -> NSVisualEffectView.Material {
        blurStrength.material(isSidebar: isSidebar)
    }

    /// Resets surface transparency to default and notifies observers.
    func resetTransparency() {
        Store.settings.removeObject(forKey: Self.surfaceTransparencyKey)
        Store.settings.removeObject(forKey: Self.legacyBackgroundTransparencyKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Resets blur strength to default and notifies observers.
    func resetBlurStrength() {
        Store.settings.removeObject(forKey: Self.blurStrengthKey)
        Store.settings.removeObject(forKey: Self.legacyStrengthKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Resets settings to default and notifies observers.
    func reset() {
        resetBlurStrength()
        Store.settings.removeObject(forKey: Self.foundationOpacityKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

typealias ChromeGlassSettings = BrowserSurfaceSettings

/// The decorative blurred and tinted browser surface.
/// Combines native AppKit FrostedGlass with user Palette.ground coloration,
/// treated as one visual material governed by surfaceOpacity = 1.0 - surfaceTransparency.
struct BrowserSurfaceView: View {
    let isSidebar: Bool
    @ObservedObject private var surface = BrowserSurfaceSettings.shared
    @ObservedObject private var glassTint = AppearanceGlassSettings.shared
    @ObservedObject private var paletteUpdates = AppearancePaletteUpdates.shared

    var body: some View {
        let _ = paletteUpdates.revision
        ZStack {
            FrostedGlass(
                material: surface.material(isSidebar: isSidebar),
                blendingMode: .behindWindow,
                cornerRadius: 0
            )

            Palette.ground
                .opacity(glassTint.tintOpacity)
        }
        .opacity(surface.surfaceOpacity)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
}

