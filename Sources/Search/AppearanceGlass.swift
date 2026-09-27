import SwiftUI
import AppKit

/// Centralized management and persistence for global appearance glass tint settings.
/// Governs the color wash / tint contribution across both browser chrome (over FrostedGlass)
/// and the New Tab page (over the artwork continuation atmosphere).
@MainActor
final class AppearanceGlassSettings: ObservableObject {
    static let shared = AppearanceGlassSettings()

    nonisolated static let didChange = Notification.Name("SearchAppearanceGlassDidChange")

    nonisolated static let newTintKey = "appearance.glassTintOpacity"
    nonisolated static let legacyTintKey = "appearance.chrome.tintOpacity"

    nonisolated static let defaultTint: Double = 0.35
    nonisolated static let tintRange: ClosedRange<Double> = 0.00...1.00
    nonisolated static let tintStep: Double = 0.05

    private init() {}

    /// Effective tint opacity layered over FrostedGlass in Chrome and atmospheric continuation in New Tab.
    var tintOpacity: Double {
        get {
            if let val = Store.settings.object(forKey: Self.newTintKey) as? Double {
                return min(max(val, Self.tintRange.lowerBound), Self.tintRange.upperBound)
            }
            // Fallback migration from legacy chrome tint key if present
            if let val = Store.settings.object(forKey: Self.legacyTintKey) as? Double {
                return min(max(val, Self.tintRange.lowerBound), Self.tintRange.upperBound)
            }
            return Self.defaultTint
        }
        set {
            let clamped = min(max(newValue, Self.tintRange.lowerBound), Self.tintRange.upperBound)
            Store.settings.set(clamped, forKey: Self.newTintKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Whether the glass tint setting differs from its default value.
    var isCustomized: Bool {
        if Store.settings.object(forKey: Self.newTintKey) != nil {
            return abs(tintOpacity - Self.defaultTint) > 0.001
        }
        if Store.settings.object(forKey: Self.legacyTintKey) != nil {
            return abs(tintOpacity - Self.defaultTint) > 0.001
        }
        return false
    }

    /// Resets glass tint to default and cleans up both new and legacy keys.
    func reset() {
        Store.settings.removeObject(forKey: Self.newTintKey)
        Store.settings.removeObject(forKey: Self.legacyTintKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// Physical Glass Tint layer sitting above colorless BrowserSurface and below artwork.
/// Provides independent color tinting using the canonical resolved Background Color (Palette.ground).
struct GlassTintSurface: View {
    @ObservedObject private var glassTint = AppearanceGlassSettings.shared
    @ObservedObject private var paletteUpdates = AppearancePaletteUpdates.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Palette.ground
            .opacity(glassTint.tintOpacity)
            .id("glass-tint-\(paletteUpdates.revision)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
