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
    let isArtworkActive: Bool

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

    // Subtle opposite-color contrast halo for text/symbols when artwork is active
    let haloColor: Color
    let haloRadius: CGFloat
    let haloY: CGFloat

    static let dark = ChromeForeground(
        isDarkForeground: true,
        isArtworkActive: false,
        ink: Color.black.opacity(0.88),
        muted: Color.black.opacity(0.60),
        faint: Color.black.opacity(0.28),
        hover: Color.black.opacity(0.08),
        wash: Color.black.opacity(0.12),
        hairline: Color.black.opacity(0.12),
        progress: Color.black.opacity(0.08),
        haloColor: .clear,
        haloRadius: 0,
        haloY: 0
    )

    static let light = ChromeForeground(
        isDarkForeground: false,
        isArtworkActive: false,
        ink: Color.white.opacity(0.92),
        muted: Color.white.opacity(0.65),
        faint: Color.white.opacity(0.30),
        hover: Color.white.opacity(0.12),
        wash: Color.white.opacity(0.16),
        hairline: Color.white.opacity(0.18),
        progress: Color.white.opacity(0.10),
        haloColor: .clear,
        haloRadius: 0,
        haloY: 0
    )

    static func make(isDark: Bool, isArtworkActive: Bool) -> ChromeForeground {
        let base: ChromeForeground = isDark ? .dark : .light
        guard isArtworkActive else { return base }
        return ChromeForeground(
            isDarkForeground: base.isDarkForeground,
            isArtworkActive: true,
            ink: base.ink,
            muted: base.muted,
            faint: base.faint,
            hover: base.hover,
            wash: base.wash,
            hairline: base.hairline,
            progress: base.progress,
            haloColor: isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.40),
            haloRadius: 1.2,
            haloY: 0.5
        )
    }
}

extension View {
    /// Applies a subtle opposite-color contrast halo when Chrome artwork is active.
    /// When artwork is absent or inactive, haloColor is .clear and radius is 0, having zero effect.
    func chromeContrastHalo(_ chrome: ChromeForeground) -> some View {
        self.shadow(color: chrome.haloColor, radius: chrome.haloRadius, x: 0, y: chrome.haloY)
    }
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
        let isVisiblyActive = Self.isChromeArtworkVisiblyActive(for: browser)
        return ChromeForeground.make(isDark: isDark, isArtworkActive: isVisiblyActive)
    }

    /// Centralized check whether Chrome artwork is visibly contributing to the window.
    static func isChromeArtworkVisiblyActive(for browser: Browser) -> Bool {
        let tab = browser.active
        let isBlank = tab?.isBlank ?? true
        let override = ChromeArtwork.overrideNewTabArtwork && ChromeArtwork.current() != nil
        let hasArtwork = override || (isBlank && (NewTabArtwork.current() ?? ChromeArtwork.current()) != nil)
        return hasArtwork && AppearanceTransparencySettings.shared.chromeArtworkOpacity > 0.001
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
        let artOpacity = CGFloat(AppearanceTransparencySettings.shared.chromeArtworkOpacity)
        let isVisiblyActive = isShowingArtwork && artOpacity > 0.001
        let alphaArt: CGFloat = isVisiblyActive ? artOpacity : 0.0

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

        let tintRGB: (r: CGFloat, g: CGFloat, b: CGFloat) = groundRGB

        let alphaTint: CGFloat = CGFloat(AppearanceGlassSettings.shared.tintOpacity)
        let cTinted = (
            r: (1.0 - alphaTint) * glassBase.r + alphaTint * tintRGB.r,
            g: (1.0 - alphaTint) * glassBase.g + alphaTint * tintRGB.g,
            b: (1.0 - alphaTint) * glassBase.b + alphaTint * tintRGB.b
        )

        // Composite artwork directly over cTinted (physical foundation wash was removed)
        let cFinal: (r: CGFloat, g: CGFloat, b: CGFloat)
        if isVisiblyActive {
            cFinal = (
                r: (1.0 - alphaArt) * cTinted.r + alphaArt * sampledArtRGB.r,
                g: (1.0 - alphaArt) * cTinted.g + alphaArt * sampledArtRGB.g,
                b: (1.0 - alphaArt) * cTinted.b + alphaArt * sampledArtRGB.b
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

/// Animatable reveal mask for Chrome artwork only.
/// Interpolates smoothly between the top tab strip and the sidebar using Motion.glide.
struct ChromeArtworkMaskShape: Shape {
    var sideWidth: CGFloat
    var topHeight: CGFloat
    var onRight: Bool = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(sideWidth, topHeight) }
        set {
            sideWidth = newValue.first
            topHeight = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if sideWidth > 0 {
            if onRight {
                path.addRect(CGRect(x: rect.width - sideWidth, y: 0, width: sideWidth, height: rect.height))
            } else {
                path.addRect(CGRect(x: 0, y: 0, width: sideWidth, height: rect.height))
            }
        }
        if topHeight > 0 {
            path.addRect(CGRect(x: 0, y: 0, width: rect.width, height: topHeight))
        }
        return path
    }
}

/// The root-level persistent Chrome background view hosting a continuous Chrome artwork hierarchy
/// clipped to ChromeArtworkMaskShape and an optional native Liquid Glass overlay.
struct PersistentChromeBackground: View {
    @ObservedObject var browser: Browser
    let sideWidth: CGFloat
    let topHeight: CGFloat
    var targetSideWidth: CGFloat = 210
    var targetTopHeight: CGFloat = 44
    var onRight: Bool? = nil
    @ObservedObject private var liquidGlass = LiquidGlassSettings.shared

    private var effectiveOnRight: Bool {
        onRight ?? (browser.prefs.sidebar && browser.prefs.sidePosition == .right)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 1. PERSISTENT CHROME ARTWORK LAYER
                // Continuous, orientation-independent image selection.
                // Smoothly morphs scale and center anchor with Motion.glide.
                // Clipped strictly by animatable ChromeArtworkMaskShape (artwork-only).
                if let tab = browser.active {
                    ChromeArtworkHost(
                        browser: browser,
                        tab: tab,
                        sideWidth: sideWidth,
                        topHeight: topHeight,
                        targetSideWidth: targetSideWidth,
                        targetTopHeight: targetTopHeight,
                        windowSize: geo.size
                    )
                    .clipShape(ChromeArtworkMaskShape(sideWidth: sideWidth, topHeight: topHeight, onRight: effectiveOnRight))
                    .zIndex(liquidGlass.position == .aboveArtwork ? 0 : 1)
                }

                // 2. NATIVE LIQUID GLASS OVERLAY (macOS 26+)
                // Positioned above or below the chrome artwork stack according to liquidGlass.position.
                NativeLiquidGlassOverlay()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(ChromeArtworkMaskShape(sideWidth: sideWidth, topHeight: topHeight, onRight: effectiveOnRight))
                    .zIndex(liquidGlass.position == .aboveArtwork ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Host view managing artwork source selection, settings observations, and lifecycle.
private struct ChromeArtworkHost: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let sideWidth: CGFloat
    let topHeight: CGFloat
    let targetSideWidth: CGFloat
    let targetTopHeight: CGFloat
    let windowSize: CGSize

    @ObservedObject private var glassTint = AppearanceGlassSettings.shared
    @ObservedObject private var transparency = AppearanceTransparencySettings.shared

    @State private var newTabImage: NSImage? = NewTabArtwork.current()
    @State private var chromeImage: NSImage? = ChromeArtwork.current()
    @State private var overrideArtwork: Bool = ChromeArtwork.overrideNewTabArtwork

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    /// Orientation-independent image resolution.
    /// Preserves exact source selection across horizontal and vertical transitions.
    private var selectedImage: NSImage? {
        let useSeparate = overrideArtwork && chromeImage != nil
        if useSeparate {
            return chromeImage
        }
        return newTabImage ?? chromeImage
    }

    /// Visibility condition:
    /// - If separate Chrome artwork override is enabled: continuously visible across all tabs.
    /// - If using default New Tab artwork: visible on blank tabs in both horizontal and sidebar modes.
    /// Orientation changes NEVER modify this condition, eliminating layout fade-outs.
    private var isShowingArtwork: Bool {
        let useSeparate = overrideArtwork && chromeImage != nil
        if useSeparate {
            return true
        }
        return tab.isBlank && (selectedImage != nil)
    }

    var body: some View {
        ZStack {
            if let image = selectedImage, windowSize.width > 0, windowSize.height > 0 {
                let wash = NewTabFade.washColor(isDark: isDark)
                let atmosphere = ArtworkAtmosphere(
                    isDark: isDark,
                    customWashColor: wash,
                    tintOpacity: glassTint.tintOpacity
                )

                ContinuousChromeArtworkView(
                    image: image,
                    sideWidth: sideWidth,
                    topHeight: topHeight,
                    targetSideWidth: targetSideWidth,
                    targetTopHeight: targetTopHeight,
                    windowWidth: windowSize.width,
                    windowHeight: windowSize.height,
                    atmosphere: atmosphere,
                    artworkOpacity: transparency.chromeArtworkOpacity
                )
                .opacity(isShowingArtwork ? 1.0 : 0.0)
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .onAppear {
            reloadArtwork()
        }
        .onReceive(NotificationCenter.default.publisher(for: NewTabArtwork.didChange)) { _ in
            reloadArtwork()
        }
        .onReceive(NotificationCenter.default.publisher(for: ChromeArtwork.didChange)) { _ in
            reloadArtwork()
        }
    }

    private func reloadArtwork() {
        overrideArtwork = ChromeArtwork.overrideNewTabArtwork

        if let currentNewTab = NewTabArtwork.current() {
            newTabImage = currentNewTab
        } else if NewTabArtwork.imageURL != nil {
            NewTabArtwork.load { loaded in
                self.newTabImage = loaded
            }
        } else {
            newTabImage = nil
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
}

/// Continuous Chrome artwork presentation conforming to Animatable.
/// Interpolates scale, horizontal focal center, hero height, and atmosphere continuously
/// between horizontal top-bar geometry and vertical sidebar geometry without unmounting or source swapping.
struct ContinuousChromeArtworkView: View, Animatable {
    let image: NSImage
    var sideWidth: CGFloat
    var topHeight: CGFloat
    let targetSideWidth: CGFloat
    let targetTopHeight: CGFloat
    let windowWidth: CGFloat
    let windowHeight: CGFloat
    let atmosphere: ArtworkAtmosphere
    let artworkOpacity: Double

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(sideWidth, topHeight) }
        set {
            sideWidth = newValue.first
            topHeight = newValue.second
        }
    }

    var body: some View {
        let effectiveTargetSideWidth = max(targetSideWidth, 1)
        let effectiveTargetTopHeight = max(targetTopHeight, 1)

        // Interpolation progress: 0.0 = fully horizontal, 1.0 = fully vertical
        let progress: CGFloat = {
            if targetSideWidth > 0 {
                return max(0, min(1, sideWidth / effectiveTargetSideWidth))
            } else if targetTopHeight > 0 {
                return max(0, min(1, 1.0 - (topHeight / effectiveTargetTopHeight)))
            } else {
                return 0
            }
        }()

        // 1. Centered focal container width:
        // Continuous full-window canvas spanning the entire window so left, right, and top masks
        // crop from the exact same stable full-window wallpaper coordinates without recentering.
        let activeWidth = windowWidth

        // 2. Reference & hero heights
        let horizRefHeight = max(effectiveTargetTopHeight, windowHeight - effectiveTargetTopHeight)
        let vertRefHeight = windowHeight
        let refHeight = (1.0 - progress) * horizRefHeight + progress * vertRefHeight
        let heroHeight = min(refHeight * 0.72, 760)

        // 3. Aspect-fill scale targets
        let imgWidth = max(image.size.width, 1)
        let imgHeight = max(image.size.height, 1)
        let scale = max(windowWidth / imgWidth, heroHeight / imgHeight)
        let fittedWidth = imgWidth * scale
        let fittedHeight = imgHeight * scale
        let centerX = windowWidth / 2

        // Complete image-based artwork & atmosphere stack (layers 1, 2, 3):
        // Full-area background foundation is owned exclusively by GlassTintSurface.
        ZStack(alignment: .topLeading) {
            // 1. Ambient base layer (75pt blur across active focal width)
            AtmosphericBaseLayer(
                image: image,
                atmosphere: atmosphere,
                viewportWidth: activeWidth,
                viewportHeight: refHeight
            )
            .frame(width: activeWidth, height: refHeight, alignment: .topLeading)

            // 2. Ambient continuation layer (54pt blur across active focal width)
            AtmosphericContinuationLayer(
                image: image,
                atmosphere: atmosphere,
                viewportWidth: activeWidth,
                viewportHeight: refHeight,
                heroHeight: heroHeight
            )

            // 3. Sharp hero layer (focal center at centerX = activeWidth / 2)
            Image(nsImage: image)
                .resizable()
                .frame(width: fittedWidth, height: fittedHeight)
                .position(x: centerX, y: fittedHeight / 2)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.22 * progress),
                            .init(color: .white.opacity(1.0 - 0.15 * progress), location: 0.22 + 0.16 * progress),
                            .init(color: .white.opacity(0.70 - 0.30 * progress), location: 0.50 + 0.10 * progress),
                            .init(color: .clear, location: 1.0 - 0.15 * progress)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: max(windowWidth, fittedWidth), height: heroHeight)
                    .position(x: centerX, y: heroHeight / 2)
                }
        }
        .opacity(artworkOpacity)
        .frame(width: windowWidth, height: windowHeight, alignment: .topLeading)
    }
}
