import SwiftUI
import AppKit

/// Representative colors extracted once from artwork off the main thread.
struct ArtworkColors: Equatable {
    let topColor: (r: CGFloat, g: CGFloat, b: CGFloat)
    let leftColor: (r: CGFloat, g: CGFloat, b: CGFloat)
    let bottomColor: (r: CGFloat, g: CGFloat, b: CGFloat)
    let averageColor: (r: CGFloat, g: CGFloat, b: CGFloat)

    static func == (lhs: ArtworkColors, rhs: ArtworkColors) -> Bool {
        lhs.topColor == rhs.topColor &&
        lhs.leftColor == rhs.leftColor &&
        lhs.bottomColor == rhs.bottomColor &&
        lhs.averageColor == rhs.averageColor
    }

    static func extract(from image: NSImage) -> ArtworkColors {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ArtworkColors(
                topColor: (0.5, 0.5, 0.5),
                leftColor: (0.5, 0.5, 0.5),
                bottomColor: (0.5, 0.5, 0.5),
                averageColor: (0.5, 0.5, 0.5)
            )
        }
        let width = 16
        let height = 16
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return ArtworkColors(
                topColor: (0.5, 0.5, 0.5),
                leftColor: (0.5, 0.5, 0.5),
                bottomColor: (0.5, 0.5, 0.5),
                averageColor: (0.5, 0.5, 0.5)
            )
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var topR: CGFloat = 0, topG: CGFloat = 0, topB: CGFloat = 0, topCount: CGFloat = 0
        var leftR: CGFloat = 0, leftG: CGFloat = 0, leftB: CGFloat = 0, leftCount: CGFloat = 0
        var bottomR: CGFloat = 0, bottomG: CGFloat = 0, bottomB: CGFloat = 0, bottomCount: CGFloat = 0
        var allR: CGFloat = 0, allG: CGFloat = 0, allB: CGFloat = 0, allCount: CGFloat = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let a = CGFloat(data[offset + 3]) / 255.0
                guard a > 0.05 else { continue }
                let r = (CGFloat(data[offset]) / 255.0) / a
                let g = (CGFloat(data[offset + 1]) / 255.0) / a
                let b = (CGFloat(data[offset + 2]) / 255.0) / a

                allR += r; allG += g; allB += b; allCount += 1

                if y <= 2 {
                    topR += r; topG += g; topB += b; topCount += 1
                }
                if x <= 2 {
                    leftR += r; leftG += g; leftB += b; leftCount += 1
                }
                if y >= height - 3 {
                    bottomR += r; bottomG += g; bottomB += b; bottomCount += 1
                }
            }
        }

        let avg = allCount > 0 ? (allR / allCount, allG / allCount, allB / allCount) : (0.5, 0.5, 0.5)
        let top = topCount > 0 ? (topR / topCount, topG / topCount, topB / topCount) : avg
        let left = leftCount > 0 ? (leftR / leftCount, leftG / leftCount, leftB / leftCount) : avg
        let bottom = bottomCount > 0 ? (bottomR / bottomCount, bottomG / bottomCount, bottomB / bottomCount) : avg

        return ArtworkColors(
            topColor: top,
            leftColor: left,
            bottomColor: bottom,
            averageColor: avg
        )
    }
}

/// Semantic foreground colors for browser chrome, adapting dynamically to the effective backdrop.
struct ChromeForeground: Equatable {
    let isDarkForeground: Bool

    // Primary text & symbols (active tab label, main icons)
    let ink: Color

    // Secondary text & symbols (inactive tab label, close button, inactive helm icons, plus icon)
    let muted: Color

    // Disabled or very faint controls
    let faint: Color

    // Hover background fill for pills & buttons
    let hover: Color

    // Active/selected pill background fill
    let wash: Color

    // Separators or hairlines
    let hairline: Color

    // Reading progress fill inside tab pill
    let progress: Color

    static let dark = ChromeForeground(
        isDarkForeground: true,
        ink: Color.black.opacity(0.88),
        muted: Color.black.opacity(0.60),
        faint: Color.black.opacity(0.28),
        hover: Color.black.opacity(0.08),
        wash: Color.black.opacity(0.12),
        hairline: Color.black.opacity(0.12),
        progress: Color.black.opacity(0.08)
    )

    static let light = ChromeForeground(
        isDarkForeground: false,
        ink: Color.white.opacity(0.92),
        muted: Color.white.opacity(0.65),
        faint: Color.white.opacity(0.30),
        hover: Color.white.opacity(0.12),
        wash: Color.white.opacity(0.16),
        hairline: Color.white.opacity(0.18),
        progress: Color.white.opacity(0.10)
    )
}

struct ChromeForegroundKey: EnvironmentKey {
    static let defaultValue: ChromeForeground = .light
}

extension EnvironmentValues {
    var chromeForeground: ChromeForeground {
        get { self[ChromeForegroundKey.self] }
        set { self[ChromeForegroundKey.self] = newValue }
    }
}

/// Resolves the effective chrome backdrop luminance and determines whether chrome controls
/// should use dark or light foreground styling with hysteresis.
@MainActor
final class ChromeLegibility: ObservableObject {
    static let shared = ChromeLegibility()

    private var previousTopStripDecision: Bool?
    private var previousSidebarDecision: Bool?
    private var previousTopStripScheme: ColorScheme?
    private var previousSidebarScheme: ColorScheme?

    private var lastLoggedTopStrip: String = ""
    private var lastLoggedSidebar: String = ""

    private init() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(invalidate), name: NewTabArtwork.didChange, object: nil)
        center.addObserver(self, selector: #selector(invalidate), name: ChromeArtwork.didChange, object: nil)
        center.addObserver(self, selector: #selector(invalidate), name: AppearanceBackground.didChange, object: nil)
        center.addObserver(self, selector: #selector(invalidate), name: BrowserSurfaceSettings.didChange, object: nil)
        center.addObserver(self, selector: #selector(invalidate), name: AppearanceGlassSettings.didChange, object: nil)
        center.addObserver(self, selector: #selector(invalidate), name: AppearanceTransparencySettings.didChange, object: nil)
    }

    @objc private func invalidate() {
        previousTopStripDecision = nil
        previousSidebarDecision = nil
        previousTopStripScheme = nil
        previousSidebarScheme = nil
        objectWillChange.send()
    }

    func foreground(for browser: Browser, isSidebar: Bool, colorScheme: ColorScheme? = nil) -> ChromeForeground {
        let isDark = resolveIsDarkForeground(for: browser, isSidebar: isSidebar, colorScheme: colorScheme)
        return isDark ? .dark : .light
    }

    func resolveIsDarkForeground(for browser: Browser, isSidebar: Bool, colorScheme: ColorScheme? = nil) -> Bool {
        let tab = browser.active
        let isBlank = tab?.isBlank ?? true

        let overrideArtwork = ChromeArtwork.overrideNewTabArtwork
        let chromeImage = ChromeArtwork.current()
        let chromeColors = ChromeArtwork.currentColors()
        let newTabImage = NewTabArtwork.current()
        let newTabColors = NewTabArtwork.currentColors()

        let artworkImage: NSImage?
        let artworkColors: ArtworkColors?

        if isSidebar {
            if overrideArtwork && chromeImage != nil {
                artworkImage = chromeImage
                artworkColors = chromeColors
            } else {
                artworkImage = nil
                artworkColors = nil
            }
        } else {
            if overrideArtwork && chromeImage != nil {
                artworkImage = chromeImage
                artworkColors = chromeColors
            } else {
                artworkImage = newTabImage ?? chromeImage
                artworkColors = newTabColors ?? chromeColors
            }
        }

        let isSystemDark: Bool
        if let colorScheme {
            isSystemDark = (colorScheme == .dark)
        } else if let appearance = NSApp?.effectiveAppearance {
            isSystemDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        } else {
            isSystemDark = false
        }

        let glassBase: (r: CGFloat, g: CGFloat, b: CGFloat) = isSystemDark
            ? (0.16, 0.16, 0.16)
            : (0.92, 0.92, 0.92)

        let useSeparate = overrideArtwork && chromeImage != nil
        let isShowingArtwork = useSeparate ? (artworkImage != nil) : (isBlank && artworkImage != nil)
        let alphaArt: CGFloat = isShowingArtwork ? 0.85 : 0.0

        let sampledArtRGB: (r: CGFloat, g: CGFloat, b: CGFloat)
        if let colors = artworkColors {
            sampledArtRGB = isSidebar ? colors.leftColor : colors.topColor
        } else {
            sampledArtRGB = (0.5, 0.5, 0.5)
        }


        // Ground color
        let groundColor = isSystemDark ? AppearanceBackground.currentDark : AppearanceBackground.currentLight
        let groundNS = groundColor.usingColorSpace(.sRGB) ?? (isSystemDark ? NSColor(white: 0.11, alpha: 1) : NSColor.white)
        let groundRGB = (r: groundNS.redComponent, g: groundNS.greenComponent, b: groundNS.blueComponent)

        // Canonical wash matches NewTabFade.washColor(isDark:): black in dark mode, ground in light mode
        let washRGB: (r: CGFloat, g: CGFloat, b: CGFloat) = isSystemDark ? (0, 0, 0) : groundRGB
        let tintRGB: (r: CGFloat, g: CGFloat, b: CGFloat) = groundRGB

        let alphaTint: CGFloat = CGFloat(AppearanceGlassSettings.shared.tintOpacity)
        let cTinted = (
            r: (1.0 - alphaTint) * glassBase.r + alphaTint * tintRGB.r,
            g: (1.0 - alphaTint) * glassBase.g + alphaTint * tintRGB.g,
            b: (1.0 - alphaTint) * glassBase.b + alphaTint * tintRGB.b
        )

        // 2. When showing artwork, composite high-density foundation then artwork over cTinted
        let cFinal: (r: CGFloat, g: CGFloat, b: CGFloat)
        if isShowingArtwork {
            let alphaFoundation: CGFloat = CGFloat(ChromeGlassSettings.shared.artworkFoundationOpacity)
            let cFoundation = (
                r: (1.0 - alphaFoundation) * cTinted.r + alphaFoundation * washRGB.r,
                g: (1.0 - alphaFoundation) * cTinted.g + alphaFoundation * washRGB.g,
                b: (1.0 - alphaFoundation) * cTinted.b + alphaFoundation * washRGB.b
            )

            cFinal = (
                r: (1.0 - alphaArt) * cFoundation.r + alphaArt * sampledArtRGB.r,
                g: (1.0 - alphaArt) * cFoundation.g + alphaArt * sampledArtRGB.g,
                b: (1.0 - alphaArt) * cFoundation.b + alphaArt * sampledArtRGB.b
            )
        } else {
            cFinal = cTinted
        }

        func linearize(_ c: CGFloat) -> CGFloat {
            let clamped = max(0, min(1, c))
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }

        let effectiveLuminance = 0.2126 * linearize(cFinal.r) + 0.7152 * linearize(cFinal.g) + 0.0722 * linearize(cFinal.b)

        // Reset hysteresis decision if appearance/colorScheme changed
        if isSidebar {
            if let colorScheme, colorScheme != previousSidebarScheme {
                previousSidebarDecision = nil
                previousSidebarScheme = colorScheme
            }
        } else {
            if let colorScheme, colorScheme != previousTopStripScheme {
                previousTopStripDecision = nil
                previousTopStripScheme = colorScheme
            }
        }

        let prevDecision = isSidebar ? previousSidebarDecision : previousTopStripDecision
        let isDarkForeground: Bool

        if effectiveLuminance >= 0.42 {
            isDarkForeground = true // Dark foreground on bright surface
        } else if effectiveLuminance <= 0.30 {
            isDarkForeground = false // Light foreground on dark surface
        } else if let prev = prevDecision {
            // Retain previous decision in deadband
            isDarkForeground = prev
        } else {
            // Initial fallback / scheme transition fallback
            isDarkForeground = effectiveLuminance >= 0.36
        }

        if isSidebar {
            previousSidebarDecision = isDarkForeground
        } else {
            previousTopStripDecision = isDarkForeground
        }

        // Debug logging on state changes
        let logKey = "\(isSidebar)-\(isBlank)-\(isShowingArtwork)-\(String(format: "%.2f", effectiveLuminance))-\(isDarkForeground)"
        let lastLog = isSidebar ? lastLoggedSidebar : lastLoggedTopStrip
        if logKey != lastLog {
            if isSidebar { lastLoggedSidebar = logKey } else { lastLoggedTopStrip = logKey }
            print("""
            [ChromeLegibility] \(isSidebar ? "Sidebar" : "Top Strip") updated:
              - Active tab isBlank: \(isBlank), showing artwork: \(isShowingArtwork)
              - Artwork sampled RGB: (\(String(format: "%.2f, %.2f, %.2f", sampledArtRGB.r, sampledArtRGB.g, sampledArtRGB.b))), opacity: \(String(format: "%.2f", alphaArt))
              - Glass base RGB: (\(String(format: "%.2f, %.2f, %.2f", glassBase.r, glassBase.g, glassBase.b)))
              - Foundation wash RGB: (\(String(format: "%.2f, %.2f, %.2f", washRGB.r, washRGB.g, washRGB.b))), opacity: \(String(format: "%.2f", ChromeGlassSettings.shared.artworkFoundationOpacity))
              - Tint RGB: (\(String(format: "%.2f, %.2f, %.2f", tintRGB.r, tintRGB.g, tintRGB.b))), tint opacity: \(String(format: "%.2f", alphaTint))
              - Final estimated effective RGB: (\(String(format: "%.2f, %.2f, %.2f", cFinal.r, cFinal.g, cFinal.b)))
              - Final effective luminance: \(String(format: "%.3f", effectiveLuminance))
              - Selected foreground: \(isDarkForeground ? "DARK" : "LIGHT")
            """)
        }

        return isDarkForeground
    }
}


/// Provider and cache for optional dedicated Chrome Artwork.
enum ChromeArtwork {
    static let didChange = Notification.Name("SearchChromeArtworkDidChange")
    static let preferenceKey = "SearchChromeArtwork"
    static let overridePreferenceKey = "appearance.chrome.overrideNewTabArtwork"

    private static var cached: (url: URL, image: NSImage, colors: ArtworkColors)?

    /// The local image URL for chrome artwork, if configured.
    static var imageURL: URL? {
        if let custom = Store.settings.string(forKey: preferenceKey), !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Whether to show separate Chrome Artwork in the chrome.
    static var overrideNewTabArtwork: Bool {
        get { Store.settings.bool(forKey: overridePreferenceKey) }
        set {
            Store.settings.set(newValue, forKey: overridePreferenceKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Sets the configured artwork path, invalidates the cache, and notifies observers.
    static func setPath(_ path: String) {
        Store.settings.set(path, forKey: preferenceKey)
        Store.settings.set(true, forKey: overridePreferenceKey)
        cached = nil
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Clears the configured artwork path, invalidates the cache, and notifies observers.
    static func clear() {
        Store.settings.removeObject(forKey: preferenceKey)
        cached = nil
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Returns the cached image synchronously if already decoded for the current URL.
    static func current() -> NSImage? {
        guard let url = imageURL else {
            cached = nil
            return nil
        }
        if let cached, cached.url == url {
            return cached.image
        }
        if let image = NSImage(contentsOf: url) {
            let colors = ArtworkColors.extract(from: image)
            cached = (url, image, colors)
            return image
        }
        return nil
    }

    /// Returns the cached artwork colors synchronously if available.
    static func currentColors() -> ArtworkColors? {
        guard let url = imageURL else {
            cached = nil
            return nil
        }
        if let cached, cached.url == url {
            return cached.colors
        }
        if let image = NSImage(contentsOf: url) {
            let colors = ArtworkColors.extract(from: image)
            cached = (url, image, colors)
            return colors
        }
        return nil
    }

    /// Loads and caches the image asynchronously.
    static func load(completion: @escaping (NSImage?) -> Void) {
        guard let url = imageURL else {
            cached = nil
            completion(nil)
            return
        }
        if let cached, cached.url == url {
            completion(cached.image)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = NSImage(contentsOf: url)
            let colors = image.map { ArtworkColors.extract(from: $0) }
            DispatchQueue.main.async {
                if let image, let colors {
                    cached = (url, image, colors)
                    completion(image)
                } else {
                    completion(nil)
                }
            }
        }
    }
}

/// Host view providing permanent frosted glass and translucent tint, with new-tab-only artwork.
struct ChromeBackgroundHost: View {
    @ObservedObject var browser: Browser
    let isSidebar: Bool
    let landing: Bool

    var body: some View {
        ChromeBackground(
            browser: browser,
            activeTab: browser.active,
            isSidebar: isSidebar,
            landing: landing
        )
        .allowsHitTesting(false)
    }
}

/// Renders the layered chrome background.
///
/// Invariant: BrowserSurfaceView is PERMANENT and NEVER unmounted or animated.
/// It continuously samples the desktop behind the NSWindow with .behindWindow blending.
/// The active tab's blank state controls ONLY the opacity of the artwork layer.
private struct ChromeBackground: View {
    @ObservedObject var browser: Browser
    let activeTab: Tab?
    let isSidebar: Bool
    let landing: Bool

    @ObservedObject private var paletteUpdates = AppearancePaletteUpdates.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let _ = paletteUpdates.revision
        let _ = colorScheme
        GeometryReader { geo in
            ZStack {
                // 1. PERSISTENT CHROME BROWSER SURFACE
                // Always alive, never conditionally unmounted, never animated.
                // FrostedGlass + Palette.ground coloration governed by surfaceOpacity.
                BrowserSurfaceView(isSidebar: isSidebar)
                    .frame(width: geo.size.width, height: geo.size.height)

                // 2. OPTIONAL ARTWORK LAYER (NEW-TAB ONLY OR SEPARATE ARTWORK)
                // Sits strictly above BrowserSurfaceView so the artwork is never tinted from above.
                if let tab = activeTab {
                    ChromeArtworkLayer(
                        browser: browser,
                        tab: tab,
                        isSidebar: isSidebar,
                        size: geo.size
                    )
                }

                // 3. LANDING / DRAG OVERLAY
                if landing {
                    Palette.hover
                        .opacity(0.85)
                }

                // 4. NATIVE LIQUID GLASS OVERLAY (macOS 26+)
                // Sits above the chrome artwork stack to refract and sample the rendered artwork.
                // Governed independently by LiquidGlassSettings (style and intensity).
                NativeLiquidGlassOverlay()
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .clipped()
        }
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
}

/// Renders the optional new-tab artwork layer and observes the active tab's blank state.
private struct ChromeArtworkLayer: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let isSidebar: Bool
    let size: CGSize

    @ObservedObject private var glass = ChromeGlassSettings.shared
    @ObservedObject private var glassTint = AppearanceGlassSettings.shared
    @ObservedObject private var transparency = AppearanceTransparencySettings.shared

    @State private var newTabImage: NSImage? = NewTabArtwork.current()
    @State private var chromeImage: NSImage? = ChromeArtwork.current()
    @State private var overrideArtwork: Bool = ChromeArtwork.overrideNewTabArtwork
    @State private var windowWidth: CGFloat = 0
    @State private var windowHeight: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var hasArtwork: Bool {
        if isSidebar {
            // SIDEBAR MODE: ONLY show artwork if separate chrome artwork is configured and enabled.
            // The default New Tab page continuation into the sidebar is completely removed.
            return overrideArtwork && chromeImage != nil
        } else {
            // HORIZONTAL TOP STRIP MODE:
            if overrideArtwork && chromeImage != nil {
                return true
            }
            return newTabImage != nil || chromeImage != nil
        }
    }

    private var isShowingArtwork: Bool {
        let useSeparate = overrideArtwork && chromeImage != nil
        if useSeparate {
            // Persistent across all tabs (blank and loaded)
            return true
        } else {
            // Contextual New Tab artwork (horizontal strip only)
            return tab.isBlank && hasArtwork
        }
    }

    var body: some View {
        ZStack {
            if hasArtwork, size.width > 0, size.height > 0 {
                artworkContent(size: size)
                    .opacity(isShowingArtwork ? 1.0 : 0.0)
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.18), value: isShowingArtwork)
        .onAppear {
            reloadArtwork()
            updateWindowGeometry()
        }
        .onReceive(NotificationCenter.default.publisher(for: NewTabArtwork.didChange)) { _ in
            reloadArtwork()
        }
        .onReceive(NotificationCenter.default.publisher(for: ChromeArtwork.didChange)) { _ in
            reloadArtwork()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
            updateWindowGeometry()
        }
    }

    private func updateWindowGeometry() {
        let win = Links.window?.contentView?.bounds ?? NSApp.keyWindow?.contentView?.bounds
        if let w = win?.width, w > 0 {
            self.windowWidth = w
        }
        if let h = win?.height, h > 0 {
            self.windowHeight = h
        }
    }

    private func reloadArtwork() {
        overrideArtwork = ChromeArtwork.overrideNewTabArtwork

        if !isSidebar {
            if let currentNewTab = NewTabArtwork.current() {
                newTabImage = currentNewTab
            } else if NewTabArtwork.imageURL != nil {
                NewTabArtwork.load { loaded in
                    self.newTabImage = loaded
                }
            } else {
                newTabImage = nil
            }
        }

        if let currentChrome = ChromeArtwork.current() {
            chromeImage = currentChrome
        } else if ChromeArtwork.imageURL != nil {
            ChromeArtwork.load { loaded in
                self.chromeImage = loaded
            }
        } else {
            chromeImage = nil
        }
    }

    private var atmosphericWashColor: Color {
        NewTabFade.washColor(isDark: isDark)
    }

    @ViewBuilder
    private func artworkContent(size: CGSize) -> some View {
        if isSidebar {
            // In sidebar mode, only separate chrome artwork is rendered when enabled.
            // Uses full vertical atmospheric progression with FrostedGlass active underneath.
            if let image = chromeImage {
                let wash = atmosphericWashColor
                let atmosphere = ArtworkAtmosphere(isDark: isDark, customWashColor: wash, tintOpacity: glassTint.tintOpacity)

                let effectiveWindowWidth = windowWidth > 0
                    ? windowWidth
                    : (Links.window?.contentView?.bounds.width ?? 1180)
                let effectiveWindowHeight = windowHeight > 0
                    ? windowHeight
                    : (Links.window?.contentView?.bounds.height ?? 800)
                let referenceWidth = max(size.width, effectiveWindowWidth)
                let referenceHeight = max(size.height, effectiveWindowHeight)
                let heroHeight = min(referenceHeight * 0.72, 760)

                ZStack(alignment: .topLeading) {
                    // 0. High-density atmosphere foundation
                    // Sits above FrostedGlass and Glass Tint, below artwork blurs.
                    // Anchors the atmosphere to NewTabFade.washColor with high density (~0.90)
                    // so the artwork blurs melt into the foundation while retaining subtle glass shimmer.
                    // Opacity is governed by artworkFoundationOpacity and global backgroundOpacity.
                    wash
                        .opacity(glass.artworkFoundationOpacity * transparency.backgroundOpacity)
                        .frame(width: size.width, height: size.height)

                    // Complete image-based artwork & atmosphere stack (layers 1, 2, 3):
                    // Fades together as a coherent artwork surface governed by artworkOpacity.
                    ZStack(alignment: .topLeading) {
                        // Virtual atmospheric canvas
                        // Rendered across the full reference width (window width) and height so blurs
                        // sample the complete artwork with lateral lighting before being clipped to the sidebar.
                        ZStack(alignment: .topLeading) {
                            // 1. Ambient base layer (75pt blur across wide virtual canvas)
                            AtmosphericBaseLayer(
                                image: image,
                                atmosphere: atmosphere,
                                viewportWidth: referenceWidth,
                                viewportHeight: referenceHeight
                            )

                            // 2. Ambient continuation layer (54pt blur across wide virtual canvas)
                            AtmosphericContinuationLayer(
                                image: image,
                                atmosphere: atmosphere,
                                viewportWidth: referenceWidth,
                                viewportHeight: referenceHeight,
                                heroHeight: heroHeight
                            )
                        }
                        .frame(width: referenceWidth, height: referenceHeight, alignment: .topLeading)
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .clipped()
                        .allowsHitTesting(false)

                        // 3. Sharp hero layer (sidebar-focused framing with dedicated smooth atmospheric handoff)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size.width, height: heroHeight, alignment: .top)
                            .clipped()
                            .mask {
                                NewTabFade.sidebarHeroMask()
                            }
                    }
                    .opacity(transparency.artworkOpacity)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .clipped()
                .allowsHitTesting(false)
            }
        } else {
            // Horizontal top tab strip mode:
            // Uses a virtual canvas sized to the real viewport height to compute atmospheric
            // blurs and hero proportions before clipping only the top 38-52pt visible slice.
            let useSeparate = overrideArtwork && chromeImage != nil
            let selectedImage = useSeparate ? chromeImage : (newTabImage ?? chromeImage)

            if let image = selectedImage {
                let wash = atmosphericWashColor
                let atmosphere = ArtworkAtmosphere(isDark: isDark, customWashColor: wash, tintOpacity: glassTint.tintOpacity)

                let effectiveWindowHeight = windowHeight > 0
                    ? windowHeight
                    : (Links.window?.contentView?.bounds.height ?? 800)
                let referenceWidth = size.width
                let referenceHeight = max(size.height, effectiveWindowHeight - size.height)
                let heroHeight = min(referenceHeight * 0.72, 760)

                ZStack(alignment: .topLeading) {
                    // 0. High-density atmosphere foundation
                    wash
                        .opacity(glass.artworkFoundationOpacity * transparency.backgroundOpacity)
                        .frame(width: referenceWidth, height: referenceHeight)

                    // Complete image-based artwork & atmosphere stack (layers 1, 2, 3):
                    // Fades together as a coherent artwork surface governed by artworkOpacity.
                    ZStack(alignment: .topLeading) {
                        // 1. Ambient base layer (75pt blur across virtual canvas)
                        AtmosphericBaseLayer(
                            image: image,
                            atmosphere: atmosphere,
                            viewportWidth: referenceWidth,
                            viewportHeight: referenceHeight
                        )

                        // 2. Ambient continuation layer (54pt blur across virtual canvas)
                        AtmosphericContinuationLayer(
                            image: image,
                            atmosphere: atmosphere,
                            viewportWidth: referenceWidth,
                            viewportHeight: referenceHeight,
                            heroHeight: heroHeight
                        )

                        // 3. Sharp hero layer (across virtual canvas)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: referenceWidth, height: heroHeight, alignment: .center)
                            .clipped()
                            .mask {
                                NewTabFade.heroBottomMask()
                            }
                    }
                    .opacity(transparency.artworkOpacity)
                }
                .frame(width: referenceWidth, height: referenceHeight, alignment: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .clipped()
                .allowsHitTesting(false)
            }
        }
    }
}
