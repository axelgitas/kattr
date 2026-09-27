import SwiftUI
import AppKit

/// Manages persistence, live change notifications, and resolution for global BrowserSurface settings.
@MainActor
final class BrowserSurfaceSettings: ObservableObject {
    static let shared = BrowserSurfaceSettings()

    static let didChange = Notification.Name("SearchBrowserSurfaceDidChange")

    static let blurSurfaceOpacityKey = "appearance.blurSurfaceOpacity"
    static let foundationOpacityKey = "appearance.chrome.artworkFoundationOpacity"

    static let defaultBlurSurfaceOpacity: Double = 1.0
    static let defaultArtworkFoundationOpacity: Double = 0.90

    static let blurSurfaceRange: ClosedRange<Double> = 0.0...1.0
    static let blurSurfaceStep: Double = 0.01

    private init() {}

    /// Perceptual blur surface opacity (0.0 = completely transparent / sharp desktop, 1.0 = full frosted glass blur).
    var blurSurfaceOpacity: Double {
        get {
            if let val = Store.settings.object(forKey: Self.blurSurfaceOpacityKey) as? Double {
                return min(max(val, Self.blurSurfaceRange.lowerBound), Self.blurSurfaceRange.upperBound)
            }
            return Self.defaultBlurSurfaceOpacity
        }
        set {
            let clamped = min(max(newValue, Self.blurSurfaceRange.lowerBound), Self.blurSurfaceRange.upperBound)
            Store.settings.set(clamped, forKey: Self.blurSurfaceOpacityKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Effective tint opacity layered over artwork/chrome (delegates to global AppearanceGlassSettings).
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

    /// Whether blur surface opacity differs from the default.
    var isBlurSurfaceCustomized: Bool {
        if Store.settings.object(forKey: Self.blurSurfaceOpacityKey) != nil {
            return abs(blurSurfaceOpacity - Self.defaultBlurSurfaceOpacity) > 0.001
        }
        return false
    }

    var isCustomized: Bool {
        isBlurSurfaceCustomized
    }

    /// Resets blur surface opacity to default and notifies observers.
    func resetBlurSurfaceOpacity() {
        Store.settings.removeObject(forKey: Self.blurSurfaceOpacityKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Resets settings to default and notifies observers.
    func reset() {
        resetBlurSurfaceOpacity()
        Store.settings.removeObject(forKey: Self.foundationOpacityKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

typealias ChromeGlassSettings = BrowserSurfaceSettings

/// The persistent full-window unmasked browser backdrop.
/// Provides exactly one continuous NSVisualEffectView covering full window bounds
/// with fixed .headerView material and behindWindow blending.
/// Opacity is governed continuously by blurSurfaceOpacity for perceptual blur strength control.
struct BrowserSurfaceView: View {
    @ObservedObject private var surface = BrowserSurfaceSettings.shared

    var body: some View {
        FrostedGlass(
            material: .headerView,
            blendingMode: .behindWindow,
            cornerRadius: 0
        )
        .opacity(surface.blurSurfaceOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
