import SwiftUI
import AppKit

/// Shared visual fade semantics connecting NewTabBackground and ChromeBackground.
enum NewTabFade {
    /// Semantic wash/ground destination color matching the New Tab canvas foundation.
    /// In Dark mode, pure black preserves saturated midnight hues; in Light mode, Palette.ground
    /// respects custom canvas tints (e.g. burgundy, navy, etc.).
    static func washColor(isDark: Bool) -> Color {
        isDark ? Color.black : Palette.ground
    }

    /// Full hero top-to-bottom dissolve mask (white at top, clear at bottom).
    static func heroBottomMask() -> LinearGradient {
        LinearGradient(
            colors: [.white, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Dedicated sidebar hero top-to-bottom atmospheric handoff mask.
    /// Holds solid opacity across the upper portion of the column, then provides a broad,
    /// smooth decline into clear well before the atmospheric continuation layer fades out,
    /// allowing the diffused optical atmosphere to bloom naturally beneath the controls.
    static func sidebarHeroMask() -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.22),
                .init(color: .white.opacity(0.85), location: 0.38),
                .init(color: .white.opacity(0.40), location: 0.60),
                .init(color: .white.opacity(0.10), location: 0.75),
                .init(color: .clear, location: 0.88)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Atmospheric wash gradient melting into washColor towards the bottom.
    static func washGradient(washColor: Color) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: washColor.opacity(0.30), location: 0.45),
                .init(color: washColor.opacity(0.75), location: 0.8),
                .init(color: washColor, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Optical atmospheric constants and parameters matching the New Tab page pipeline.
struct ArtworkAtmosphere {
    let isDark: Bool
    let washColor: Color
    let baseTopOpacity: Double
    let baseMidOpacity: Double
    let baseFloorOpacity: Double
    let ambientContinuationOpacity: Double

    init(isDark: Bool, customWashColor: Color? = nil) {
        self.isDark = isDark
        self.washColor = customWashColor ?? NewTabFade.washColor(isDark: isDark)
        self.baseTopOpacity = isDark ? 0.30 : 0.18
        self.baseMidOpacity = isDark ? 0.22 : 0.13
        self.baseFloorOpacity = isDark ? 0.16 : 0.09
        self.ambientContinuationOpacity = isDark ? 0.22 : 0.14
    }
}

/// 1. Artwork-derived ambient base layer (75pt blur).
/// Fullscreen diffused backdrop scaled slightly beyond viewport bounds so blur
/// never exposes edges. Attenuated with a gradient mask that preserves a nonzero
/// floor at the bottom, guaranteeing the artwork's dominant color survives
/// all the way to the bottom of the canvas.
struct AtmosphericBaseLayer: View {
    let image: NSImage
    let atmosphere: ArtworkAtmosphere
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat

    init(image: NSImage, atmosphere: ArtworkAtmosphere, size: CGSize) {
        self.image = image
        self.atmosphere = atmosphere
        self.viewportWidth = size.width
        self.viewportHeight = size.height
    }

    init(image: NSImage, atmosphere: ArtworkAtmosphere, viewportWidth: CGFloat, viewportHeight: CGFloat) {
        self.image = image
        self.atmosphere = atmosphere
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: viewportWidth, height: viewportHeight)
            .clipped()
            .scaleEffect(1.15)
            .blur(radius: 75)
            .frame(width: viewportWidth, height: viewportHeight)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(atmosphere.baseTopOpacity), location: 0.0),
                        .init(color: .white.opacity(atmosphere.baseMidOpacity), location: 0.45),
                        .init(color: .white.opacity(atmosphere.baseFloorOpacity), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }
}

/// 2. Ambient continuation layer (54pt blur).
/// Reuses the exact same scale and center coordinates as the hero so there is
/// zero spatial displacement or double-image around the hero transition line.
/// Diffused with blur and darkened with a wash gradient so that artwork color
/// continues naturally around and below heroHeight.
struct AtmosphericContinuationLayer: View {
    let image: NSImage
    let atmosphere: ArtworkAtmosphere
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let heroHeight: CGFloat

    init(image: NSImage, atmosphere: ArtworkAtmosphere, size: CGSize, heroHeight: CGFloat) {
        self.image = image
        self.atmosphere = atmosphere
        self.viewportWidth = size.width
        self.viewportHeight = size.height
        self.heroHeight = heroHeight
    }

    init(image: NSImage, atmosphere: ArtworkAtmosphere, viewportWidth: CGFloat, viewportHeight: CGFloat, heroHeight: CGFloat) {
        self.image = image
        self.atmosphere = atmosphere
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.heroHeight = heroHeight
    }

    var body: some View {
        let scale = max(viewportWidth / max(image.size.width, 1), heroHeight / max(image.size.height, 1))
        let fittedWidth = image.size.width * scale
        let fittedHeight = image.size.height * scale

        ZStack(alignment: .top) {
            Image(nsImage: image)
                .resizable()
                .frame(width: fittedWidth, height: fittedHeight)
                .position(x: viewportWidth / 2, y: heroHeight / 2)
                .blur(radius: 54)

            NewTabFade.washGradient(washColor: atmosphere.washColor)
        }
        .frame(width: viewportWidth, height: viewportHeight, alignment: .top)
        .clipped()
        .opacity(atmosphere.ambientContinuationOpacity)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0.0),
                    .init(color: .white, location: 0.5),
                    .init(color: .white.opacity(0.7), location: 0.75),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
