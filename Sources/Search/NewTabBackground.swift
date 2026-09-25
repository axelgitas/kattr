import SwiftUI
import AppKit


/// Zeron-inspired artwork treatment for Search's blank / new-tab page.
///
/// Occupies the upper portion of the page viewport (~72% height, capped at 760pt),
/// cropped with aspect-fill, faded progressively into Palette.ground toward the bottom,
/// and softly feathered around the centered Omnibox so the artwork continues gently
/// behind the field rather than forming a harsh cutout.
struct NewTabBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage? = NewTabArtwork.current()
    @State private var ready = false

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        GeometryReader { proxy in
            if let image {
                artworkView(
                    image: image,
                    size: proxy.size,
                    globalMinY: proxy.frame(in: .global).minY
                )
                .opacity(ready ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .onAppear { loadArtwork() }
        .onReceive(NotificationCenter.default.publisher(for: NewTabArtwork.didChange)) { _ in
            loadArtwork()
        }
    }

    private func loadArtwork() {
        if let current = NewTabArtwork.current() {
            self.image = current
            self.ready = true
        } else if NewTabArtwork.imageURL != nil {
            self.ready = false
            NewTabArtwork.load { loaded in
                self.image = loaded
                withAnimation(.easeOut(duration: 0.12)) {
                    self.ready = loaded != nil
                }
            }
        } else {
            self.image = nil
            self.ready = false
        }
    }

    @ViewBuilder
    private func artworkView(image: NSImage, size: CGSize, globalMinY: CGFloat) -> some View {
        let viewportWidth = size.width
        let viewportHeight = size.height
        let heroHeight = min(viewportHeight * 0.72, 760)

        if viewportWidth > 0 && viewportHeight > 0 && heroHeight > 0 {
            // Omnibox geometry derived from Search's actual Omnibox and Metrics layout.
            let omniboxWidth = Metrics.fieldWidth
            let omniboxHeight = Omnibox.fieldHeight
            let clearance: CGFloat = 8
            let cornerRadius = Omnibox.cornerRadius + clearance
            let feather = min(max(heroHeight * 0.52, 120), 280)

            // Centered horizontally within the page viewport.
            let omniboxCenterX = viewportWidth / 2
            let omniboxOriginX = omniboxCenterX - omniboxWidth / 2

            // Omnibox is centered in the window with Omnibox.lift bottom padding.
            // In page coordinates (offset by globalMinY from window top):
            let windowHeight = viewportHeight + globalMinY
            let omniboxCenterYInWindow = (windowHeight - Omnibox.lift) / 2
            let omniboxCenterYInPage = omniboxCenterYInWindow - globalMinY
            let omniboxOriginY = omniboxCenterYInPage - omniboxHeight / 2

            // The cutout region clears the omnibox and extends through the hero's bottom,
            // preventing the image from fading back in below the field.
            let clearedRect = CGRect(
                x: omniboxOriginX - clearance,
                y: omniboxOriginY - clearance,
                width: omniboxWidth + 2 * clearance,
                height: max(omniboxOriginY + omniboxHeight, heroHeight) - (omniboxOriginY - clearance)
            )

            let atmosphere = ArtworkAtmosphere(isDark: isDark)

            ZStack(alignment: .topLeading) {
                // 0. Base canvas foundation:
                // Dark appearance anchors to pure black so that the artwork stains the canvas
                // with deep, rich midnight hues (e.g. purple -> deep near-black purple,
                // red -> deep burgundy, blue -> deep navy) without desaturating into
                // Search's neutral gray (Palette.ground = 0.11).
                // Light appearance anchors to Palette.ground (pure white) for a clean,
                // readable, gently tinted paper canvas.
                atmosphere.washColor
                    .frame(width: viewportWidth, height: viewportHeight)

                // 1. Artwork-derived ambient base:
                // Fullscreen diffused backdrop scaled slightly beyond viewport bounds so blur
                // never exposes edges. Attenuated with a gradient mask that preserves a nonzero
                // floor at the bottom, guaranteeing the artwork's dominant color survives
                // all the way to the bottom of the canvas.
                AtmosphericBaseLayer(
                    image: image,
                    atmosphere: atmosphere,
                    viewportWidth: viewportWidth,
                    viewportHeight: viewportHeight
                )

                // 2. Ambient continuation layer:
                // Reuses the exact same scale and center coordinates as the hero so there is
                // zero spatial displacement or double-image around the hero transition line.
                // Diffused with blur and darkened with a wash gradient so that artwork color
                // continues naturally around and below heroHeight.
                AtmosphericContinuationLayer(
                    image: image,
                    atmosphere: atmosphere,
                    viewportWidth: viewportWidth,
                    viewportHeight: viewportHeight,
                    heroHeight: heroHeight
                )

                // 3. Main sharp hero layer with feathered omnibox cutout and top-to-bottom fade:
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: viewportWidth, height: heroHeight, alignment: .center)
                    .clipped()
                    .mask {
                        // Full-height progressive fade into the background, combined with
                        // a feathered 50% contrast underlay cutout around the omnibox.
                        NewTabFade.heroBottomMask()
                        .mask {
                            ZStack {
                                Color.white

                                CutoutMaskShape(cutoutRect: clearedRect, cornerRadius: cornerRadius)
                                    .fill(Color.black.opacity(0.5))
                                    .blur(radius: feather / 2)
                            }
                            .compositingGroup()
                            .luminanceToAlpha()
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// A shape matching the clearance boundary around the omnibox, rounded at the top
/// and extending open through the bottom of the hero area.
private struct CutoutMaskShape: Shape {
    let cutoutRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        let x = cutoutRect.minX
        let y = cutoutRect.minY
        let w = cutoutRect.width
        let h = cutoutRect.height

        guard w > 0, h > 0 else { return path }

        path.move(to: CGPoint(x: x, y: y + h))
        path.addLine(to: CGPoint(x: x, y: y + r))
        path.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x + r, y: y), radius: r)
        path.addLine(to: CGPoint(x: x + w - r, y: y))
        path.addArc(tangent1End: CGPoint(x: x + w, y: y), tangent2End: CGPoint(x: x + w, y: y + r), radius: r)
        path.addLine(to: CGPoint(x: x + w, y: y + h))
        path.closeSubpath()
        return path
    }
}

/// Minimal, isolated provider for new-tab background artwork.
///
/// Decodes images off the main thread and caches the NSImage in memory so that
/// SwiftUI view evaluations never perform file I/O or redundant decodes.
enum NewTabArtwork {
    static let didChange = Notification.Name("SearchNewTabArtworkDidChange")
    static let preferenceKey = "SearchNewTabArtwork"

    private static var cached: (url: URL, image: NSImage, colors: ArtworkColors)?

    /// The local image URL for new-tab artwork, if configured.
    /// Checks Store.settings under "SearchNewTabArtwork" or files in Search's data folder.
    static var imageURL: URL? {
        if let custom = Store.settings.string(forKey: preferenceKey), !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        for name in ["newtab.png", "newtab.jpg", "background.png", "background.jpg"] {
            let file = Store.file(name)
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        return nil
    }

    /// Sets the configured artwork path, invalidates the cache, and notifies observers.
    static func setPath(_ path: String) {
        Store.settings.set(path, forKey: preferenceKey)
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
