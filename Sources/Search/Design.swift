import SwiftUI
import AppKit

// Lifted from Office Inspiration, with the ground turned white: there the work
// floats on an off-white canvas, here the page *is* the ground and everything
// the browser draws has to get out of its way.
//
// Every colour is a pair — one for a light window, one for a dark — and
// resolves itself against whatever appearance the window has. The window
// takes its appearance from the app, and the app from Settings › Appearance:
// light, dark, or whatever the Mac is doing. Nothing else in the code knows
// which it is.
/// Tiny MainActor notifier responsible solely for triggering SwiftUI invalidation when the palette changes.
@MainActor
final class AppearancePaletteUpdates: ObservableObject {
    static let shared = AppearancePaletteUpdates()
    @Published private(set) var revision: UInt = 0

    func changed() {
        revision &+= 1
    }
}

enum Palette {
    static var ground: Color { Color(nsColor: NS.ground) }
    static var ink: Color { Color(nsColor: NS.ink) }
    static var muted: Color { Color(nsColor: NS.muted) }
    static var faint: Color { Color(nsColor: NS.faint) }
    static var hairline: Color { Color(nsColor: NS.hairline) }
    static var wash: Color { Color(nsColor: NS.wash) }
    /// The live pin: among squares that already wear a faint grey, the one
    /// you are on stands out from them as a live row does from the white.
    static var pinLive: Color { Color(nsColor: NS.pinLive) }
    static var hover: Color { Color(nsColor: NS.hover) }
    /// The only two that aren't grey: a connection nobody can read on the
    /// way, and one anybody can (see SiteCard.swift).
    static let safe = Color(nsColor: NS.safe)           // green-700 · green-400
    static let unsafe = Color(nsColor: NS.unsafe)       // amber-700 · amber-400

    /// The same colours for the AppKit corners of the app — a text field's
    /// ink, a window's background — which want an NSColor and keep it.
    enum NS {
        static var ground: NSColor { dynamic { $0.ground } }
        static var ink: NSColor { dynamic { $0.ink } }
        static var muted: NSColor { dynamic { $0.muted } }
        static var faint: NSColor { dynamic { $0.faint } }
        static var hairline: NSColor { dynamic { $0.hairline } }
        static var wash: NSColor { dynamic { $0.wash } }
        static let pinLive = pair(0.90, 0.21)
        static var hover: NSColor { dynamic { $0.hover } }
        /// The resting traffic lights, drawn by hand when the app is behind.
        static let resting = pair(0.80, 0.30)
        static let safe = tint(light: (0.08, 0.50, 0.24), dark: (0.29, 0.87, 0.50))
        static let unsafe = tint(light: (0.71, 0.33, 0.04), dark: (0.98, 0.75, 0.14))

        private static func dynamic(_ select: @escaping (AppearanceBackground.NeutralRamp) -> NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                AppearanceBackground.resolved(select, for: appearance)
            }
        }

        private static func tint(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            NSColor(name: nil) { appearance in
                let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }

        private static func pair(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
            NSColor(name: nil) { appearance in
                let dim = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(white: dim ? dark : light, alpha: 1)
            }
        }
    }
}

/// Centralized management and persistence for custom user-configured background colors
/// and derivation of the adaptive neutral palette.
enum AppearanceBackground {
    static let didChange = Notification.Name("SearchAppearanceBackgroundDidChange")

    static let lightKey = "appearance.background.light"
    static let darkKey = "appearance.background.dark"

    static let defaultLight = NSColor(white: 1.000, alpha: 1.0)
    static let defaultDark = NSColor(white: 0.110, alpha: 1.0)

    struct NeutralRamp {
        let ground: NSColor
        let ink: NSColor
        let muted: NSColor
        let faint: NSColor
        let hairline: NSColor
        let wash: NSColor
        let hover: NSColor
    }

    static let defaultLightRamp = NeutralRamp(
        ground: defaultLight,
        ink: NSColor(white: 0.090, alpha: 1.0),
        muted: NSColor(white: 0.550, alpha: 1.0),
        faint: NSColor(white: 0.830, alpha: 1.0),
        hairline: NSColor(white: 0.910, alpha: 1.0),
        wash: NSColor(white: 0.937, alpha: 1.0),
        hover: NSColor(white: 0.965, alpha: 1.0)
    )

    static let defaultDarkRamp = NeutralRamp(
        ground: defaultDark,
        ink: NSColor(white: 0.930, alpha: 1.0),
        muted: NSColor(white: 0.580, alpha: 1.0),
        faint: NSColor(white: 0.320, alpha: 1.0),
        hairline: NSColor(white: 0.200, alpha: 1.0),
        wash: NSColor(white: 0.175, alpha: 1.0),
        hover: NSColor(white: 0.150, alpha: 1.0)
    )

    /// Derives an adaptive neutral ramp from a custom ground color using WCAG relative luminance
    /// and component blending toward the highest contrast endpoint (black or white).
    static func adaptiveRamp(from ground: NSColor) -> NeutralRamp {
        guard let srgb = ground.usingColorSpace(.sRGB) else {
            return defaultLightRamp
        }
        let rg = max(0, min(1, srgb.redComponent))
        let gg = max(0, min(1, srgb.greenComponent))
        let bg = max(0, min(1, srgb.blueComponent))

        func linearize(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        func luminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
            0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
        }

        func contrastRatio(_ l1: CGFloat, _ l2: CGFloat) -> CGFloat {
            (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }

        let lg = luminance(r: rg, g: gg, b: bg)
        let contrastWhite = contrastRatio(1.0, lg)
        let contrastBlack = contrastRatio(0.0, lg)

        let toWhite = contrastWhite > contrastBlack
        let endpoint: CGFloat = toWhite ? 1.0 : 0.0

        func blend(t: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            let rOut = (1.0 - t) * rg + t * endpoint
            let gOut = (1.0 - t) * gg + t * endpoint
            let bOut = (1.0 - t) * bg + t * endpoint
            return (max(0, min(1, rOut)), max(0, min(1, gOut)), max(0, min(1, bOut)))
        }

        func makeColor(_ rgb: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1.0)
        }

        // Primary text: ink. Guarantee >= 4.5:1 contrast against ground.
        var inkT: CGFloat = toWhite ? 0.92 : 0.91
        var inkRGB = blend(t: inkT)
        var inkLum = luminance(r: inkRGB.0, g: inkRGB.1, b: inkRGB.2)
        while inkT < 1.0 && contrastRatio(inkLum, lg) < 4.5 {
            inkT = min(1.0, inkT + 0.01)
            inkRGB = blend(t: inkT)
            inkLum = luminance(r: inkRGB.0, g: inkRGB.1, b: inkRGB.2)
        }

        // Secondary text: muted. Aim for >= 3.0:1 contrast, bounded below ink.
        var mutedT: CGFloat = toWhite ? 0.53 : 0.45
        let maxMutedT = max(mutedT, inkT - 0.15)
        var mutedRGB = blend(t: mutedT)
        var mutedLum = luminance(r: mutedRGB.0, g: mutedRGB.1, b: mutedRGB.2)
        while mutedT < maxMutedT && contrastRatio(mutedLum, lg) < 3.0 {
            mutedT = min(maxMutedT, mutedT + 0.01)
            mutedRGB = blend(t: mutedT)
            mutedLum = luminance(r: mutedRGB.0, g: mutedRGB.1, b: mutedRGB.2)
        }

        let faintT: CGFloat = toWhite ? 0.24 : 0.17
        let hairlineT: CGFloat = toWhite ? 0.10 : 0.09
        let washT: CGFloat = toWhite ? 0.073 : 0.063
        let hoverT: CGFloat = toWhite ? 0.045 : 0.035

        let faintRGB = blend(t: faintT)
        let hairlineRGB = blend(t: hairlineT)
        let washRGB = blend(t: washT)
        let hoverRGB = blend(t: hoverT)

        return NeutralRamp(
            ground: ground,
            ink: makeColor(inkRGB),
            muted: makeColor(mutedRGB),
            faint: makeColor(faintRGB),
            hairline: makeColor(hairlineRGB),
            wash: makeColor(washRGB),
            hover: makeColor(hoverRGB)
        )
    }

    static func ramp(forDark isDark: Bool) -> NeutralRamp {
        if isDark {
            if let custom = customDark {
                return adaptiveRamp(from: custom)
            } else {
                return defaultDarkRamp
            }
        } else {
            if let custom = customLight {
                return adaptiveRamp(from: custom)
            } else {
                return defaultLightRamp
            }
        }
    }

    static func resolved(_ select: (NeutralRamp) -> NSColor, for appearance: NSAppearance) -> NSColor {
        let dim = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ramp = ramp(forDark: dim)
        return select(ramp)
    }

    /// Resolves the effective background NSColor for the given appearance.
    static func resolvedColor(for appearance: NSAppearance) -> NSColor {
        resolved({ $0.ground }, for: appearance)
    }

    /// Parses a 6-digit hex string into an sRGB NSColor.
    static func color(from hex: String) -> NSColor? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let val = UInt64(clean, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    /// Converts an NSColor to a 6-digit sRGB hex string (#RRGGBB).
    static func hex(from nsColor: NSColor) -> String? {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(max(0, min(1, srgb.redComponent)) * 255.0))
        let g = Int(round(max(0, min(1, srgb.greenComponent)) * 255.0))
        let b = Int(round(max(0, min(1, srgb.blueComponent)) * 255.0))
        guard (0...255).contains(r), (0...255).contains(g), (0...255).contains(b) else { return nil }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Converts a SwiftUI Color to a 6-digit sRGB hex string (#RRGGBB).
    static func hex(from color: Color) -> String? {
        hex(from: NSColor(color))
    }

    /// Current custom NSColor for light mode, if configured and valid.
    static var customLight: NSColor? {
        guard let hex = Store.settings.string(forKey: lightKey) else { return nil }
        return color(from: hex)
    }

    /// Current custom NSColor for dark mode, if configured and valid.
    static var customDark: NSColor? {
        guard let hex = Store.settings.string(forKey: darkKey) else { return nil }
        return color(from: hex)
    }

    private static func notifyChanged() {
        NotificationCenter.default.post(name: didChange, object: nil)
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                AppearancePaletteUpdates.shared.changed()
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AppearancePaletteUpdates.shared.changed()
                }
            }
        }
    }

    /// Sets the light background color from an NSColor or Color.
    /// If conversion to sRGB fails, the previous setting is preserved.
    static func setLight(_ color: NSColor) {
        guard let hex = hex(from: color) else { return }
        Store.settings.set(hex, forKey: lightKey)
        notifyChanged()
    }

    static func setLight(_ color: Color) {
        setLight(NSColor(color))
    }

    /// Sets the dark background color from an NSColor or Color.
    /// If conversion to sRGB fails, the previous setting is preserved.
    static func setDark(_ color: NSColor) {
        guard let hex = hex(from: color) else { return }
        Store.settings.set(hex, forKey: darkKey)
        notifyChanged()
    }

    static func setDark(_ color: Color) {
        setDark(NSColor(color))
    }

    /// Resets the light background color to default.
    static func resetLight() {
        Store.settings.removeObject(forKey: lightKey)
        notifyChanged()
    }

    /// Resets the dark background color to default.
    static func resetDark() {
        Store.settings.removeObject(forKey: darkKey)
        notifyChanged()
    }

    /// Current effective NSColor for light mode (custom or default).
    static var currentLight: NSColor {
        customLight ?? defaultLight
    }

    /// Current effective NSColor for dark mode (custom or default).
    static var currentDark: NSColor {
        customDark ?? defaultDark
    }
}

/// Light, dark, or the Mac's own — the one choice that colours everything.
enum Look: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// What the app is told to be. Nothing, for "system": the app then
    /// follows the Mac, and changes with it.
    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    /// Set on the app rather than on the window, so every panel, alert and
    /// sheet — and every page, which follows the window it is in — agrees.
    ///
    /// Never from inside whatever is happening when it is asked for: the
    /// switch in Settings changes it from within an animation, over a panel
    /// in transition, and re-skinning every window in the middle of that is
    /// how a window ends up with a layer that takes clicks and shows
    /// nothing. The next turn of the run loop is soon enough.
    func apply() {
        let wanted = appearance
        DispatchQueue.main.async {
            guard NSApp.appearance !== wanted, NSApp.appearance?.name != wanted?.name else { return }
            NSApp.appearance = wanted
        }
    }
}

enum Metrics {
    /// The tab strip. The window's title bar is grown to match it so the
    /// traffic lights come down with the tabs — otherwise giving the row room
    /// to breathe just leaves it sitting below three buttons it used to line
    /// up with.
    static let strip: CGFloat = 52
    /// Where the first tab starts. The traffic lights run from 19 to 79 —
    /// measured, not guessed — so this leaves them the same air on their right
    /// that the window gives them on their left.
    static let lights: CGFloat = 100
    /// Back, forward and reload, at the far end of the row beside the
    /// bookmarks: three doors and the air before the next one.
    static let helm: CGFloat = 3 * 26 + 2 * 2 + 8
    /// The same three doors again, in the sidebar, where they sit right of
    /// the lights instead. The column already has 10 of horizontal padding
    /// of its own before this even starts, so this is the lights' own edge
    /// (79) less that padding, plus a sliver of air — not the full breathing
    /// room a tab row gets, because the sidebar's minimum width doesn't have
    /// it to give.
    static let sideLights: CGFloat = 72
    /// The band left at the top when there is no strip: just enough for the
    /// traffic lights to sit in, and nothing else.
    static let bare: CGFloat = 34
    /// Tabs are a fixed width rather than the width of their titles, so the
    /// cross always lands in the same place and the row never rearranges
    /// itself while you read it. They give way when there are too many:
    /// narrower than tabTitled they show their site's mark alone, and they
    /// stop at tabMinWidth, the mark and its air. Past that the row scrolls,
    /// inside its own edges.
    static let tabWidth: CGFloat = 186
    static let tabTitled: CGFloat = 80
    static let tabMinWidth: CGFloat = 36
    static let tabGap: CGFloat = 2
    /// A pinned tab is a square the height of the row, holding one letter.
    static let pinWidth: CGFloat = 30
    /// The square at the end of the row that opens a new page.
    static let plusWidth: CGFloat = 30
    /// The address field, in both the places it shows up.
    static let fieldWidth: CGFloat = 560
    /// The column of titles down the left, in the way that has one.
    static let side: CGFloat = 232
    static let sideMin: CGFloat = 176
    static let sideMax: CGFloat = 440
}

// One spring for anything that moves between two places, one for anything that
// arrives or leaves. Using the same two everywhere is most of why a thing feels
// like a single piece of software rather than a pile of views.
// When macOS Reduce Motion is on in System Settings, transitions become
// immediate so the interface does not jump or slide.
enum Motion {
    /// Whether interface transitions should be immediate, following the
    /// Mac's own accessibility setting.
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var glide: Animation? {
        reduced ? nil : .spring(response: 0.34, dampingFraction: 0.82)
    }

    static var settle: Animation? {
        reduced ? nil : .spring(response: 0.30, dampingFraction: 0.86)
    }

    static var quick: Animation? {
        reduced ? nil : .easeOut(duration: 0.14)
    }
}

/// Search's mark — Drice's Subtract.svg, a pill with an S cut out of it,
/// read from its own path data rather than loaded from a file, so it stays a
/// crisp vector at any size. No plate, no square behind it: the mark draws exactly
/// what the source file has and nothing it doesn't, the way every other icon
/// in this app is a bare shape rather than a shape on a background.
struct Logomark: Shape {
    /// The source's own canvas: Subtract.svg, 608 × 276, nothing outside it.
    static let canvas = CGSize(width: 608, height: 276)

    /// A pill with an S cut out of it. The same path as the website's mark.
    private static let data = "M469.443 0C545.471 0.00013198 607.103 61.6325 607.104 137.66C607.104 213.688 545.471 275.321 469.443 275.321H137.66C61.6323 275.321 0 213.688 0 137.66C0.00016085 61.6325 61.6325 0.000140192 137.66 0H469.443ZM138.104 51.5977C127.234 51.5977 117.512 53.5115 108.938 57.3389C100.518 61.0132 93.8581 66.2188 88.959 72.9551C84.2132 79.5381 81.8398 87.3464 81.8398 96.3789C81.8399 105.258 83.6773 112.607 87.3516 118.425C91.0258 124.089 95.9251 128.682 102.049 132.203C108.173 135.571 114.833 138.327 122.028 140.471L151.652 149.197C158.389 151.188 163.9 154.249 168.187 158.383C172.473 162.516 174.617 168.028 174.617 174.917C174.617 182.572 171.402 188.849 164.972 193.748C158.695 198.494 150.122 200.867 139.252 200.867C132.21 200.867 125.702 199.413 119.731 196.504C113.914 193.442 109.091 189.308 105.264 184.103C101.436 178.744 99.2169 172.697 98.6045 165.961H97.6855L75.4102 171.013C76.3287 180.658 79.697 189.308 85.5146 196.963C91.3322 204.618 98.9103 210.665 108.249 215.104C117.741 219.544 128.076 221.765 139.252 221.765C151.193 221.765 161.68 219.774 170.713 215.794C179.746 211.813 186.711 206.225 191.61 199.029C196.662 191.834 199.188 183.414 199.188 173.769C199.188 164.124 197.352 156.239 193.678 150.115C190.003 143.838 185.104 138.863 178.98 135.188C172.857 131.514 166.044 128.605 158.542 126.462L128.229 117.735C121.799 115.898 116.516 113.219 112.383 109.698C108.402 106.177 106.412 101.354 106.412 95.2305C106.412 88.188 109.168 82.6758 114.68 78.6953C120.344 74.5619 128.152 72.4951 138.104 72.4951C147.901 72.4952 155.939 74.9448 162.216 79.8438C168.493 84.7428 172.397 91.1729 173.928 99.1338H174.847L196.663 93.8525C195.745 85.5853 192.605 78.3131 187.247 72.0361C181.889 65.6061 174.923 60.6306 166.35 57.1094C157.929 53.4351 148.514 51.5977 138.104 51.5977Z"

    func path(in rect: CGRect) -> Path {
        // Fit the canvas into whatever frame this is given, centred, at the
        // larger scale that still keeps it inside — an SVG viewBox's "meet".
        let scale = min(rect.width / Logomark.canvas.width, rect.height / Logomark.canvas.height)
        let ox = rect.midX - Logomark.canvas.width * scale / 2
        let oy = rect.midY - Logomark.canvas.height * scale / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }
        var path = Path()
        var last = CGPoint.zero
        var start = CGPoint.zero
        for (c, n) in Logomark.commands {
            switch c {
            case "M": last = CGPoint(x: n[0], y: n[1]); start = last; path.move(to: pt(n[0], n[1]))
            case "L": last = CGPoint(x: n[0], y: n[1]); path.addLine(to: pt(n[0], n[1]))
            case "H": last.x = n[0]; path.addLine(to: pt(last.x, last.y))
            case "V": last.y = n[0]; path.addLine(to: pt(last.x, last.y))
            case "C":
                var k = 0
                while k + 5 < n.count {
                    path.addCurve(to: pt(n[k + 4], n[k + 5]), control1: pt(n[k], n[k + 1]), control2: pt(n[k + 2], n[k + 3]))
                    last = CGPoint(x: n[k + 4], y: n[k + 5])
                    k += 6
                }
            case "Z": path.closeSubpath(); last = start
            default: break
            }
        }
        return path
    }

    /// Read once. Absolute M, L, H, V, C, Z — what Figma writes for a
    /// flattened shape, and nothing else is needed.
    private static let commands: [(Character, [CGFloat])] = {
        var out: [(Character, [CGFloat])] = []
        var current: Character?
        var numbers: [CGFloat] = []
        var token = ""
        func flush() {
            if !token.isEmpty, let v = Double(token) { numbers.append(CGFloat(v)) }
            token = ""
        }
        for ch in data {
            if "MLHVCZ".contains(ch) {
                flush()
                if let current { out.append((current, numbers)) }
                current = ch
                numbers = []
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "-" && !token.isEmpty {
                flush()
                token = "-"
            } else {
                token.append(ch)
            }
        }
        flush()
        if let current { out.append((current, numbers)) }
        return out
    }()
}

/// Wrong address, said without a dialog: the field shivers and stops.
struct Shake: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard !Motion.reduced else { return ProjectionTransform(.identity) }
        // Three there-and-backs, tapering to nothing, so it settles rather than
        // stopping mid-swing.
        let decay = 1 - travel
        return ProjectionTransform(
            CGAffineTransform(translationX: sin(travel * .pi * 6) * 7 * decay, y: 0)
        )
    }
}

/// A non-interactive NSVisualEffectView configured for in-window or behind-window blending so that
/// underlying content softly shows through with native macOS backdrop blur.
struct FrostedGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> GlassView {
        let view = GlassView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        if cornerRadius > 0 {
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
        return view
    }

    func updateNSView(_ view: GlassView, context: Context) {
        if view.material != material {
            view.material = material
        }

        if view.blendingMode != blendingMode {
            view.blendingMode = blendingMode
        }

        if view.state != .active {
            view.state = .active
        }

        let targetCornerRadius = cornerRadius > 0 ? cornerRadius : 0
        let targetMasksToBounds = cornerRadius > 0

        if view.layer?.cornerRadius != targetCornerRadius {
            view.layer?.cornerRadius = targetCornerRadius
        }

        if view.layer?.masksToBounds != targetMasksToBounds {
            view.layer?.masksToBounds = targetMasksToBounds
        }
    }

    final class GlassView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A non-interactive, decorative NSGlassEffectView configured for native macOS Liquid Glass appearance.
/// Only available on macOS 26.0 and later.
@available(macOS 26.0, *)
final class DecorativeGlassEffectView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// A non-interactive NSViewRepresentable wrapping native NSGlassEffectView for macOS 26+.
/// Provides the Liquid Glass optical layer (refraction, specular highlights, tinting)
/// while guaranteeing complete hit-test transparency.
@available(macOS 26.0, *)
struct NativeLiquidGlassView: NSViewRepresentable {
    var style: NSGlassEffectView.Style = .regular
    var cornerRadius: CGFloat = 0
    var tintColor: NSColor? = nil

    func makeNSView(context: Context) -> DecorativeGlassEffectView {
        let view = DecorativeGlassEffectView()
        view.wantsLayer = true
        view.style = style
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = false
        }
        return view
    }

    func updateNSView(_ view: DecorativeGlassEffectView, context: Context) {
        view.style = style
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = false
        }
    }
}

/// Discrete visual styles for the large-area native Liquid Glass overlay.
enum LiquidGlassStyle: String, CaseIterable, Identifiable {
    case off
    case clear
    case regular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .clear: return "Clear"
        case .regular: return "Regular"
        }
    }

    @available(macOS 26.0, *)
    var appKitStyle: NSGlassEffectView.Style? {
        switch self {
        case .off: return nil
        case .clear: return .clear
        case .regular: return .regular
        }
    }
}

/// Large-area Liquid Glass layer position relative to artwork.
enum LiquidGlassPosition: String, CaseIterable, Identifiable {
    case belowArtwork
    case aboveArtwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .belowArtwork: return "Below Artwork"
        case .aboveArtwork: return "Above Artwork"
        }
    }
}

/// Centralized management and persistence for the large-area Liquid Glass overlay settings.
/// Governs style (.off, .clear, .regular), opacity, and position independently of BrowserSurface.
@MainActor
final class LiquidGlassSettings: ObservableObject {
    static let shared = LiquidGlassSettings()

    static let didChange = Notification.Name("SearchLiquidGlassDidChange")

    static let styleKey = "appearance.liquidGlass.style"
    static let intensityKey = "appearance.liquidGlass.intensity"
    static let positionKey = "appearance.liquidGlassPosition"

    static let defaultStyle: LiquidGlassStyle = .off
    static let defaultIntensity: Double = 1.0
    static let defaultPosition: LiquidGlassPosition = .aboveArtwork

    static let intensityRange: ClosedRange<Double> = 0.0...1.0
    static let intensityStep: Double = 0.05

    private init() {}

    /// Large-area Liquid Glass overlay style.
    var style: LiquidGlassStyle {
        get {
            if let raw = Store.settings.string(forKey: Self.styleKey),
               let parsed = LiquidGlassStyle(rawValue: raw) {
                return parsed
            }
            return Self.defaultStyle
        }
        set {
            Store.settings.set(newValue.rawValue, forKey: Self.styleKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Large-area Liquid Glass optical strength / opacity (0.0 = completely transparent, 1.0 = fully present).
    var intensity: Double {
        get {
            if let val = Store.settings.object(forKey: Self.intensityKey) as? Double {
                return min(max(val, Self.intensityRange.lowerBound), Self.intensityRange.upperBound)
            }
            return Self.defaultIntensity
        }
        set {
            let clamped = min(max(newValue, Self.intensityRange.lowerBound), Self.intensityRange.upperBound)
            Store.settings.set(clamped, forKey: Self.intensityKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Large-area Liquid Glass layer position relative to artwork.
    var position: LiquidGlassPosition {
        get {
            if let raw = Store.settings.string(forKey: Self.positionKey),
               let parsed = LiquidGlassPosition(rawValue: raw) {
                return parsed
            }
            return Self.defaultPosition
        }
        set {
            Store.settings.set(newValue.rawValue, forKey: Self.positionKey)
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// Whether the style setting differs from the default (.off).
    var isStyleCustomized: Bool {
        if Store.settings.object(forKey: Self.styleKey) != nil {
            return style != Self.defaultStyle
        }
        return false
    }

    /// Whether the intensity setting differs from the default (1.0).
    var isIntensityCustomized: Bool {
        if Store.settings.object(forKey: Self.intensityKey) != nil {
            return abs(intensity - Self.defaultIntensity) > 0.001
        }
        return false
    }

    /// Whether the position setting differs from the default (.aboveArtwork).
    var isPositionCustomized: Bool {
        if Store.settings.object(forKey: Self.positionKey) != nil {
            return position != Self.defaultPosition
        }
        return false
    }

    /// Resets the overlay style to .off.
    func resetStyle() {
        Store.settings.removeObject(forKey: Self.styleKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Resets the overlay intensity to 1.0 (100%).
    func resetIntensity() {
        Store.settings.removeObject(forKey: Self.intensityKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Resets the overlay position to .aboveArtwork.
    func resetPosition() {
        Store.settings.removeObject(forKey: Self.positionKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Resets all settings to default.
    func reset() {
        resetStyle()
        resetIntensity()
        resetPosition()
    }
}

private struct LiquidGlassRestoreOpacityKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var liquidGlassRestoreOpacity: Double {
        get { self[LiquidGlassRestoreOpacityKey.self] }
        set { self[LiquidGlassRestoreOpacityKey.self] = newValue }
    }
}

/// A non-interactive Liquid Glass overlay view for macOS 26+.
/// Positioned above artwork layers so NSGlassEffectView refracts and samples the rendered artwork,
/// governed independently by LiquidGlassSettings (style and intensity) with zero hit-testing.
struct NativeLiquidGlassOverlay: View {
    @ObservedObject private var settings = LiquidGlassSettings.shared
    @Environment(\.liquidGlassRestoreOpacity) private var restoreOpacity

    var body: some View {
        if #available(macOS 26.0, *),
           let appKitStyle = settings.style.appKitStyle {
            NativeLiquidGlassView(
                style: appKitStyle,
                cornerRadius: 0,
                tintColor: nil
            )
            .opacity(settings.intensity * restoreOpacity)
            .allowsHitTesting(false)
        }
    }
}



