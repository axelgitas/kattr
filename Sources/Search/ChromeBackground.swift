import SwiftUI
import AppKit

/// Representative colors extracted once from artwork off the main thread.
struct ArtworkColors: Equatable {
    let topColor: (r: CGFloat, g: CGFloat, b: CGFloat)
    let leftColor: (r: CGFloat, g: CGFloat, b: CGFloat)
    let averageColor: (r: CGFloat, g: CGFloat, b: CGFloat)

    static func == (lhs: ArtworkColors, rhs: ArtworkColors) -> Bool {
        lhs.topColor == rhs.topColor && lhs.leftColor == rhs.leftColor && lhs.averageColor == rhs.averageColor
    }

    static func extract(from image: NSImage) -> ArtworkColors {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ArtworkColors(
                topColor: (0.5, 0.5, 0.5),
                leftColor: (0.5, 0.5, 0.5),
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
                averageColor: (0.5, 0.5, 0.5)
            )
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var topR: CGFloat = 0, topG: CGFloat = 0, topB: CGFloat = 0, topCount: CGFloat = 0
        var leftR: CGFloat = 0, leftG: CGFloat = 0, leftB: CGFloat = 0, leftCount: CGFloat = 0
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
            }
        }

        let avg = allCount > 0 ? (allR / allCount, allG / allCount, allB / allCount) : (0.5, 0.5, 0.5)
        let top = topCount > 0 ? (topR / topCount, topG / topCount, topB / topCount) : avg
        let left = leftCount > 0 ? (leftR / leftCount, leftG / leftCount, leftB / leftCount) : avg

        return ArtworkColors(
            topColor: top,
            leftColor: left,
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

        // 1. Composite artwork over glass
        let c1 = (
            r: (1.0 - alphaArt) * glassBase.r + alphaArt * sampledArtRGB.r,
            g: (1.0 - alphaArt) * glassBase.g + alphaArt * sampledArtRGB.g,
            b: (1.0 - alphaArt) * glassBase.b + alphaArt * sampledArtRGB.b
        )

        // Ground color
        let groundColor = isSystemDark ? AppearanceBackground.currentDark : AppearanceBackground.currentLight
        let groundNS = groundColor.usingColorSpace(.sRGB) ?? (isSystemDark ? NSColor(white: 0.11, alpha: 1) : NSColor.white)
        let groundRGB = (r: groundNS.redComponent, g: groundNS.greenComponent, b: groundNS.blueComponent)
        let washRGB = isSystemDark ? (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0)) : groundRGB

        let alphaWash: CGFloat
        if isShowingArtwork {
            if isSidebar {
                alphaWash = isSystemDark ? 0.75 : 0.65
            } else {
                alphaWash = isSystemDark ? 0.35 : 0.60
            }
        } else {
            alphaWash = 0.0
        }

        // 2. Composite readability wash over c1
        let c2 = (
            r: (1.0 - alphaWash) * c1.r + alphaWash * washRGB.r,
            g: (1.0 - alphaWash) * c1.g + alphaWash * washRGB.g,
            b: (1.0 - alphaWash) * c1.b + alphaWash * washRGB.b
        )

        // 3. Composite permanent Palette.ground.opacity(0.35) tint over c2
        let alphaTint: CGFloat = 0.35
        let cFinal = (
            r: (1.0 - alphaTint) * c2.r + alphaTint * groundRGB.r,
            g: (1.0 - alphaTint) * c2.g + alphaTint * groundRGB.g,
            b: (1.0 - alphaTint) * c2.b + alphaTint * groundRGB.b
        )

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
              - Readability wash RGB: (\(String(format: "%.2f, %.2f, %.2f", washRGB.r, washRGB.g, washRGB.b))), opacity: \(String(format: "%.2f", alphaWash))
              - Palette.ground RGB: (\(String(format: "%.2f, %.2f, %.2f", groundRGB.r, groundRGB.g, groundRGB.b))), tint opacity: \(String(format: "%.2f", alphaTint))
              - Final estimated effective RGB: (\(String(format: "%.2f, %.2f, %.2f", cFinal.r, cFinal.g, cFinal.b)))
              - Final effective luminance: \(String(format: "%.3f", effectiveLuminance))
              - Selected foreground: \(isDarkForeground ? "DARK" : "LIGHT")
            """)
        }

        return isDarkForeground
    }
}

/// Placement mathematics reproducing the exact scale and hero geometry from NewTabBackground for the top tab strip.
struct ArtworkHeroPlacement {
    let scale: CGFloat
    let fittedWidth: CGFloat
    let fittedHeight: CGFloat
    let heroHeight: CGFloat
    let pageWidth: CGFloat
    let pageHeight: CGFloat

    init(pageWidth: CGFloat, pageHeight: CGFloat, imageSize: CGSize) {
        self.pageWidth = max(pageWidth, 1)
        self.pageHeight = max(pageHeight, 1)
        self.heroHeight = min(self.pageHeight * 0.72, 760)
        let s = max(self.pageWidth / max(imageSize.width, 1), self.heroHeight / max(imageSize.height, 1))
        self.scale = s
        self.fittedWidth = imageSize.width * s
        self.fittedHeight = imageSize.height * s
    }

    /// Image center in local coordinates of the top tab strip container.
    /// Page hero center in page coords: (pageWidth / 2, heroHeight / 2).
    /// Page top is at window y = Metrics.strip.
    /// TabBar container origin in window coords is (0, 0).
    /// TabBar local image center: (pageWidth / 2, Metrics.strip + heroHeight / 2).
    func localCenter() -> CGPoint {
        CGPoint(x: pageWidth / 2, y: Metrics.strip + heroHeight / 2)
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
    }
}

/// Renders the layered chrome background.
///
/// Invariant: FrostedGlass and the translucent chrome tint are PERMANENT and NEVER unmounted or animated.
/// They continuously sample the desktop behind the NSWindow with .behindWindow blending.
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
                // 1. PERMANENT FROSTED GLASS
                // Always alive, never conditionally unmounted, never animated.
                // Samples the desktop behind the window using AppKit's native compositor.
                FrostedGlass(
                    material: isSidebar ? .sidebar : .headerView,
                    blendingMode: .behindWindow,
                    cornerRadius: 0
                )

                // 2. OPTIONAL ARTWORK LAYER (NEW-TAB ONLY)
                // In sidebar mode: ONLY shown if Separate Chrome Artwork is configured and enabled.
                // In horizontal tabs mode: continues NewTabArtwork or displays Separate Chrome Artwork.
                if let tab = activeTab {
                    ChromeArtworkLayer(
                        browser: browser,
                        tab: tab,
                        isSidebar: isSidebar,
                        size: geo.size
                    )
                }

                // 3. PERMANENT TRANSLUCENT TINT
                // Adaptive tint derived from active Palette.ground so chrome harmonizes
                // with custom canvas colors while keeping the desktop visible.
                // Sits above glass on loaded pages, and above glass + artwork on new tabs.
                Palette.ground
                    .opacity(0.35)

                // 4. LANDING / DRAG OVERLAY
                if landing {
                    Palette.hover
                        .opacity(0.85)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// Renders the optional new-tab artwork layer and observes the active tab's blank state.
private struct ChromeArtworkLayer: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let isSidebar: Bool
    let size: CGSize

    @State private var newTabImage: NSImage? = NewTabArtwork.current()
    @State private var chromeImage: NSImage? = ChromeArtwork.current()
    @State private var overrideArtwork: Bool = ChromeArtwork.overrideNewTabArtwork

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    /// Grounding overlay color matching the foundation and bottom fade of NewTabBackground.
    private var washColor: Color {
        NewTabFade.washColor(isDark: isDark)
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
                    .opacity(isShowingArtwork ? 0.85 : 0.0)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isShowingArtwork)
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

    @ViewBuilder
    private func artworkContent(size: CGSize) -> some View {
        if isSidebar {
            // In sidebar mode, only separate chrome artwork is rendered when enabled.
            // Uses a long top-to-bottom dissolve matching NewTabFade semantics.
            if let image = chromeImage {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .clipped()

                    // Apply NewTab-style vertical atmospheric wash overlay melting into washColor towards the bottom
                    NewTabFade.washGradient(washColor: washColor)
                }
                .mask {
                    NewTabFade.heroBottomMask()
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        } else {
            // Horizontal top tab strip mode:
            let useSeparate = overrideArtwork && chromeImage != nil
            let selectedImage = useSeparate ? chromeImage : (newTabImage ?? chromeImage)

            if let image = selectedImage {
                ZStack {
                    if useSeparate {
                        // Separate chrome artwork: aspect-fill to chrome container bounds
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size.width, height: size.height, alignment: .center)
                            .clipped()
                    } else {
                        // New Tab artwork continuation:
                        // 1. Full chrome bounds: atmospheric artwork bleed fills the entire area
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size.width, height: size.height, alignment: .center)
                            .scaleEffect(1.25)
                            .blur(radius: 54)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .opacity(0.85)

                        // 2. Exact continuation painted only where its source geometry intersects,
                        // uncovered area is completely transparent (clear).
                        exactContinuation(image: image, size: size)
                    }

                    // Top strip readability wash
                    topStripReadabilityWash(size: size)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
    }

    /// Readability wash overlay for the horizontal top tab strip.
    /// Represents the top slice of the New Tab fade: artwork opacity stays high across the strip,
    /// with the same NewTabFade washColor subtly increasing vertically toward the bottom.
    @ViewBuilder
    private func topStripReadabilityWash(size: CGSize) -> some View {
        LinearGradient(
            stops: [
                .init(color: washColor.opacity(isDark ? 0.18 : 0.30), location: 0.0),
                .init(color: washColor.opacity(isDark ? 0.32 : 0.50), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func exactContinuation(image: NSImage, size: CGSize) -> some View {
        let currentWindowSize = Links.window?.contentView?.bounds.size
        let effectiveWindowWidth = (currentWindowSize?.width ?? 0) > 100
            ? currentWindowSize!.width
            : size.width
        let effectiveWindowHeight = (currentWindowSize?.height ?? 0) > 100
            ? currentWindowSize!.height
            : size.height + 742

        let pageWidth = effectiveWindowWidth
        let pageHeight = max(1, effectiveWindowHeight - Metrics.strip)

        let placement = ArtworkHeroPlacement(
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            imageSize: image.size
        )
        let center = placement.localCenter()

        let imgMinX = center.x - placement.fittedWidth / 2
        let imgMinY = center.y - placement.fittedHeight / 2

        let imgRect = CGRect(x: imgMinX, y: imgMinY, width: placement.fittedWidth, height: placement.fittedHeight)
        let chromeRect = CGRect(origin: .zero, size: size)
        let intersection = imgRect.intersection(chromeRect)

        if !intersection.isNull && !intersection.isEmpty {
            Image(nsImage: image)
                .resizable()
                .frame(width: placement.fittedWidth, height: placement.fittedHeight)
                .position(x: center.x, y: center.y)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                .mask {
                    continuationMask(
                        size: size,
                        imgMinY: imgMinY
                    )
                }
        }
    }

    @ViewBuilder
    private func continuationMask(
        size: CGSize,
        imgMinY: CGFloat
    ) -> some View {
        let vFadeStart = max(0, imgMinY) / max(size.height, 1)
        let vFadeEnd = min(size.height, imgMinY + 16) / max(size.height, 1)

        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: vFadeStart),
                .init(color: .white, location: max(vFadeStart + 0.01, vFadeEnd)),
                .init(color: .white, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
