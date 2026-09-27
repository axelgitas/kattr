import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Everything there is to set. Pages down the left, one page at a time on
/// the right, each a short list of lines with a hairline between them —
/// nothing to scroll through, nothing to hunt for. The same white and
/// hairline as the rest of the app; the same pill for the page you are on
/// as for the tab you are on.
struct SettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var shield = Shield.shared
    @State private var isDefault = Links.isDefault
    @State private var page: Page = Page(rawValue: Store.settings.string(forKey: "settings.page") ?? "") ?? .general
    @State private var artworkURL: URL? = NewTabArtwork.imageURL
    @State private var artworkThumbnail: NSImage? = NewTabArtwork.current()
    @State private var chromeArtworkURL: URL? = ChromeArtwork.imageURL
    @State private var chromeArtworkThumbnail: NSImage? = ChromeArtwork.current()
    @State private var useSeparateChromeArtwork: Bool = ChromeArtwork.overrideNewTabArtwork
    @ObservedObject private var paletteUpdates = AppearancePaletteUpdates.shared
    @ObservedObject private var surfaceSettings = BrowserSurfaceSettings.shared
    @ObservedObject private var glassTintSettings = AppearanceGlassSettings.shared
    @ObservedObject private var transparencySettings = AppearanceTransparencySettings.shared
    @ObservedObject private var liquidGlassSettings = LiquidGlassSettings.shared

    enum Page: String, CaseIterable, Identifiable {
        case general, tabs, extensions, passwords, downloads, privacy, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .tabs: return "Tabs"
            case .extensions: return "Extensions"
            case .passwords: return "Passwords"
            case .downloads: return "Downloads"
            case .privacy: return "Privacy"
            case .about: return "About"
            }
        }
        var icon: String {
            switch self {
            case .general: return "macwindow"
            case .tabs: return "rectangle.split.3x1"
            case .extensions: return "puzzlepiece.extension"
            case .passwords: return "key"
            case .downloads: return "arrow.down.circle"
            case .privacy: return "hand.raised"
            case .about: return "info.circle"
            }
        }
    }

    private static let rail: CGFloat = 168
    private static let width: CGFloat = 660
    private static let height: CGFloat = 500

    var body: some View {
        let _ = paletteUpdates.revision
        HStack(spacing: 0) {
            pages
            Rectangle().fill(Palette.hairline).frame(width: 1)
            content
        }
        .frame(width: SettingsPanel.width, height: SettingsPanel.height)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
        .onChange(of: page) { _, page in Store.settings.set(page.rawValue, forKey: "settings.page") }
        .onAppear {
            updateArtworkState()
            updateChromeArtworkState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NewTabArtwork.didChange)) { _ in
            updateArtworkState()
        }
        .onReceive(NotificationCenter.default.publisher(for: ChromeArtwork.didChange)) { _ in
            updateChromeArtworkState()
        }
        .onChange(of: useSeparateChromeArtwork) { _, newValue in
            ChromeArtwork.overrideNewTabArtwork = newValue
        }
    }

    // MARK: - the rail

    private var pages: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            ForEach(Page.allCases) { item in
                PageRow(page: item, on: page == item) { page = item }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: SettingsPanel.rail, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.wash.opacity(0.45), in: Rectangle())
    }

    private struct PageRow: View {
        let page: Page
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 9) {
                    Image(systemName: page.icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                    Text(page.title)
                        .font(.system(size: 13, weight: on ? .medium : .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.75) : Palette.muted))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? Palette.ground : (hovering ? Palette.hover : .clear))
                        .shadow(color: .black.opacity(on ? 0.06 : 0), radius: 3, y: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    // MARK: - the page

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Door(icon: "xmark", help: "Done   esc") { browser.tuning = false }
            }
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .general: general
                    case .tabs: tabs
                    case .extensions: ExtensionsPage(browser: browser)
                    case .passwords: passwords
                    case .downloads: downloads
                    case .privacy: privacy
                    case .about: about
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - general

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Caption("Appearance")
                Card {
                    Line("Appearance", "Light, dark, or whatever the Mac is doing — pages follow it too") {
                        Segmented(options: Look.allCases.map { ($0, $0.title) }, selection: $prefs.look)
                    }
                    Rule()
                    Line("New Tab Background", artworkDetail) {
                        artworkControls
                    }
                    Rule()
                    Line("Chrome Artwork", chromeArtworkDetail) {
                        chromeArtworkControls
                    }
                    if chromeArtworkURL != nil {
                        Rule()
                        Line("Use Separate Chrome Artwork", "Use this artwork for browser chrome on every tab. When off, the sidebar shows only frosted glass and background tint.") {
                            Switch(on: $useSeparateChromeArtwork)
                        }
                    }
                    Rule()
                    Line("Artwork Transparency", "Opacity of the artwork image and diffused atmosphere") {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { transparencySettings.artworkTransparency },
                                    set: { transparencySettings.artworkTransparency = $0 }
                                ),
                                in: AppearanceTransparencySettings.range,
                                step: AppearanceTransparencySettings.step
                            )
                            .frame(width: 90)

                            Text("\(Int(round(transparencySettings.artworkTransparency * 100)))%")
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                                .frame(width: 34, alignment: .trailing)

                            ZStack(alignment: .trailing) {
                                Pill("Reset") {
                                    transparencySettings.resetArtwork()
                                }
                                .fixedSize()
                                .opacity(transparencySettings.isArtworkCustomized ? 1 : 0)
                                .allowsHitTesting(transparencySettings.isArtworkCustomized)
                            }
                            .frame(width: 52, alignment: .trailing)
                        }
                    }
                    Rule()
                    Line("Glass Tint", "Color tint layered over the frosted glass and atmosphere") {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { glassTintSettings.tintOpacity },
                                    set: { glassTintSettings.tintOpacity = $0 }
                                ),
                                in: AppearanceGlassSettings.tintRange,
                                step: AppearanceGlassSettings.tintStep
                            )
                            .frame(width: 90)

                            Text("\(Int(round(glassTintSettings.tintOpacity * 100)))%")
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                                .frame(width: 34, alignment: .trailing)

                            ZStack(alignment: .trailing) {
                                Pill("Reset") {
                                    glassTintSettings.reset()
                                }
                                .fixedSize()
                                .opacity(glassTintSettings.isCustomized ? 1 : 0)
                                .allowsHitTesting(glassTintSettings.isCustomized)
                            }
                            .frame(width: 52, alignment: .trailing)
                        }
                    }
                    Rule()
                    Line("Blur Surface", "Diffusion strength of the background frosted glass") {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { surfaceSettings.blurSurfaceOpacity },
                                    set: { surfaceSettings.blurSurfaceOpacity = $0 }
                                ),
                                in: BrowserSurfaceSettings.blurSurfaceRange,
                                step: BrowserSurfaceSettings.blurSurfaceStep
                            )
                            .frame(width: 90)

                            Text("\(Int(round(surfaceSettings.blurSurfaceOpacity * 100)))%")
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                                .frame(width: 34, alignment: .trailing)

                            ZStack(alignment: .trailing) {
                                Pill("Reset") {
                                    surfaceSettings.resetBlurSurfaceOpacity()
                                }
                                .fixedSize()
                                .opacity(surfaceSettings.isBlurSurfaceCustomized ? 1 : 0)
                                .allowsHitTesting(surfaceSettings.isBlurSurfaceCustomized)
                            }
                            .frame(width: 52, alignment: .trailing)
                        }
                    }
                    Rule()
                    Line("Liquid Glass", "Native Liquid Glass refraction layer over the browser surface") {
                        HStack(spacing: 8) {
                            Segmented(
                                options: LiquidGlassStyle.allCases.map { ($0, $0.title) },
                                selection: Binding(
                                    get: { liquidGlassSettings.style },
                                    set: { liquidGlassSettings.style = $0 }
                                )
                            )

                            ZStack(alignment: .trailing) {
                                Pill("Reset") {
                                    liquidGlassSettings.resetStyle()
                                }
                                .fixedSize()
                                .opacity(liquidGlassSettings.isStyleCustomized ? 1 : 0)
                                .allowsHitTesting(liquidGlassSettings.isStyleCustomized)
                            }
                            .frame(width: 52, alignment: .trailing)
                        }
                    }
                    Rule()
                    Line("Liquid Glass Intensity", "Optical strength of the native Liquid Glass overlay") {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { liquidGlassSettings.intensity },
                                    set: { liquidGlassSettings.intensity = $0 }
                                ),
                                in: LiquidGlassSettings.intensityRange,
                                step: LiquidGlassSettings.intensityStep
                            )
                            .frame(width: 90)
                            .disabled(liquidGlassSettings.style == .off)

                            Text("\(Int(round(liquidGlassSettings.intensity * 100)))%")
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                                .frame(width: 34, alignment: .trailing)

                            ZStack(alignment: .trailing) {
                                Pill("Reset") {
                                    liquidGlassSettings.resetIntensity()
                                }
                                .fixedSize()
                                .opacity(liquidGlassSettings.isIntensityCustomized ? 1 : 0)
                                .allowsHitTesting(liquidGlassSettings.isIntensityCustomized)
                            }
                            .frame(width: 52, alignment: .trailing)
                        }
                        .opacity(liquidGlassSettings.style == .off ? 0.45 : 1)
                    }
                    Rule()
                    Line("Light background", "Canvas color in light mode") {
                        HStack(spacing: 8) {
                            ColorPicker("", selection: lightBinding, supportsOpacity: false)
                                .labelsHidden()

                            if AppearanceBackground.customLight != nil {
                                Pill("Reset") {
                                    AppearanceBackground.resetLight()
                                }
                                .fixedSize()
                            }
                        }
                    }
                    Rule()
                    Line("Dark background", "Canvas color in dark mode") {
                        HStack(spacing: 8) {
                            ColorPicker("", selection: darkBinding, supportsOpacity: false)
                                .labelsHidden()

                            if AppearanceBackground.customDark != nil {
                                Pill("Reset") {
                                    AppearanceBackground.resetDark()
                                }
                                .fixedSize()
                            }
                        }
                    }
                }
            }

            Card {
                Line(
                    "Open links from other apps",
                    isDefault ? "Search is the default browser on this Mac" : "Mail, Slack and the rest still send links elsewhere"
                ) {
                    if isDefault {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 24)
                    } else {
                        Pill("Make default", filled: true) {
                            Links.becomeDefault { worked in
                                isDefault = Links.isDefault
                                browser.announce(worked && isDefault ? "Links now open here" : "macOS didn't change it")
                            }
                        }
                    }
                }
                Rule()
                Line("Search with", searchDetail) {
                    Picker("", selection: $prefs.engine) {
                        ForEach(Engine.allCases) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if prefs.engine == .custom {
                    ZStack(alignment: .leading) {
                        if prefs.customEngine.isEmpty {
                            Text("https://example.com/search?q=%s")
                                .foregroundStyle(Palette.muted.opacity(0.8))
                        }
                        TextField("", text: $prefs.customEngine)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Palette.ink)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 11)
                }
                Rule()
                Line("Correct spelling as you type", "macOS's autocorrect inside pages — the one that capitalises for you") {
                    Switch(on: $prefs.autocorrect)
                }
                Rule()
                Line("Peek at a link with a shift-click", "Its page opens in a panel over the one you're reading. Escape puts it away; the other button keeps it as a tab") {
                    Switch(on: $prefs.peeksLinks)
                }
                Rule()
                Line("Open links from other apps in a small window", "To read and close, or keep with Open in Search (⌘O)") {
                    Switch(on: $prefs.littleLinks)
                }
                Rule()
                Line("Show where links go", "Point at a link and its address shows at the bottom of the page") {
                    Switch(on: $prefs.showsLinks)
                }
                Rule()
                Line("Scroll with the middle button", "Click the wheel on a page, then move the mouse up or down to scroll, as on Windows. Click again to stop") {
                    Switch(on: $prefs.autoScroll)
                }
                Rule()
                Line("Pages at 120 Hz", "Animations and scrolling in pages at up to 120 frames a second on a screen that can, instead of 60 as in Safari. Uses more battery. Open tabs follow when reloaded") {
                    Switch(on: $prefs.fastPages)
                }
                Rule()
                Line("Flick the floating video to a corner", "Two fingers on it send it to the corner or edge they point at, instead of pushing it along. Dragging still puts it anywhere") {
                    Switch(on: $prefs.floatFlicks)
                }
                Rule()
                Line("Float the video when you switch tabs", "A video playing on YouTube and the like comes out into its floating window when you go to another tab, and back when you return. ⇧⌘P still floats one by hand") {
                    Switch(on: $prefs.floatsOnLeave)
                }
                Rule()
                Line("Float the video when you switch apps", "A video playing on the site you're on comes out into its floating window as another app comes to the front, and goes back into its tab when you return") {
                    Switch(on: $prefs.floatsAway)
                }
                Rule()
                Line("Let a script drive Search", "A local socket for testing. Its tabs open beside yours with a flask on them and never take over — see ./bench") {
                    Switch(on: $prefs.bench)
                }
            }
        }
    }

    private var searchDetail: String {
        guard prefs.engine == .custom else { return "Where words that aren't an address go" }
        guard Engine.accepts(prefs.customEngine) else {
            return "An http or https address with %s where the words go. Until then, Google"
        }
        return "Words go to \(prefs.engine.name(custom: prefs.customEngine))"
    }

    private var artworkDetail: String {
        if let url = artworkURL {
            return url.lastPathComponent
        }
        return "Shown on blank tabs behind the address field"
    }

    @ViewBuilder
    private var artworkControls: some View {
        if artworkURL != nil {
            HStack(spacing: 8) {
                if let thumb = artworkThumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                }
                Pill("Change…") { chooseArtwork() }
                Pill("Remove") { removeArtwork() }
            }
        } else {
            Pill("Choose Image…") { chooseArtwork() }
        }
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        NewTabArtwork.setPath(url.path)
    }

    private func removeArtwork() {
        NewTabArtwork.clear()
    }

    private func updateArtworkState() {
        artworkURL = NewTabArtwork.imageURL
        if let current = NewTabArtwork.current() {
            artworkThumbnail = current
        } else if artworkURL != nil {
            NewTabArtwork.load { loaded in
                self.artworkThumbnail = loaded
            }
        } else {
            artworkThumbnail = nil
        }
    }

    private var chromeArtworkDetail: String {
        if let url = chromeArtworkURL {
            return url.lastPathComponent
        }
        return "Optional separate artwork for the tab strip or sidebar"
    }

    @ViewBuilder
    private var chromeArtworkControls: some View {
        if chromeArtworkURL != nil {
            HStack(spacing: 8) {
                if let thumb = chromeArtworkThumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                }
                Pill("Change…") { chooseChromeArtwork() }
                Pill("Remove") { removeChromeArtwork() }
            }
        } else {
            Pill("Choose Image…") { chooseChromeArtwork() }
        }
    }

    private func chooseChromeArtwork() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ChromeArtwork.setPath(url.path)
        useSeparateChromeArtwork = true
    }

    private func removeChromeArtwork() {
        ChromeArtwork.clear()
    }

    private func updateChromeArtworkState() {
        chromeArtworkURL = ChromeArtwork.imageURL
        if let current = ChromeArtwork.current() {
            chromeArtworkThumbnail = current
        } else if chromeArtworkURL != nil {
            ChromeArtwork.load { loaded in
                self.chromeArtworkThumbnail = loaded
            }
        } else {
            chromeArtworkThumbnail = nil
        }
        useSeparateChromeArtwork = ChromeArtwork.overrideNewTabArtwork
    }

    private var lightBinding: Binding<Color> {
        Binding(
            get: {
                let _ = paletteUpdates.revision
                return Color(nsColor: AppearanceBackground.currentLight)
            },
            set: { newColor in
                AppearanceBackground.setLight(newColor)
            }
        )
    }

    private var darkBinding: Binding<Color> {
        Binding(
            get: {
                let _ = paletteUpdates.revision
                return Color(nsColor: AppearanceBackground.currentDark)
            },
            set: { newColor in
                AppearanceBackground.setDark(newColor)
            }
        )
    }

    // MARK: - tabs

    private var tabs: some View {
        Card {
            Line("Tabs in a sidebar", "Down the left instead of across the top. Pull its edge to make it wider; double-click the edge to reset.") {
                Switch(on: Binding(
                    get: { prefs.sidebar },
                    set: { on in withAnimation(Motion.glide) { prefs.sidebar = on } }
                ))
            }
            if prefs.sidebar {
                Rule()
                Line("Hide the sidebar until the pointer reaches the edge", "The page takes the whole window; push against its left edge for the tabs. ⌘S keeps them out.") {
                    Switch(on: $prefs.sideHides)
                }
            }
            Rule()
            Line("Tabs show", "Beside the title, and on a pinned square") {
                Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
            }
            Rule()
            Line("Show the bookmarks bar", "Your bookmarks in a row above the page, folders opening as menus. It folds away with the tabs") {
                Switch(on: $prefs.bookmarksBar)
            }
            Rule()
            Line("Show how far you've read", "The tab you're on fills with grey as you scroll down the page") {
                Switch(on: $prefs.showsReading)
            }
            Rule()
            Line("Sleep tabs you aren't using", "After half an hour away they come back where you left them. Pinned tabs, sound, calls and anything typed stay awake.") {
                Switch(on: $prefs.sleepsTabs)
            }
            Rule()
            Line("Spaces", "Separate sets of tabs, signed in where the others are or starting afresh, switched with ⌃1–⌃9, two fingers sideways over the column, or the space's icon. Mission Control's own ⌃1–⌃9, if you turned them on, take those keys first.") {
                Switch(on: $prefs.usesSpaces)
            }
        }
    }

    // MARK: - passwords

    /// Says so when a password manager extension has taken the saving over.
    private var savingDetail: String {
        if #available(macOS 15.4, *), let name = Extensions.shared.passwordSavingTakenBy {
            return "\(name) does the saving — it asked Search not to offer"
        }
        return "Asked once per site, never again for a site you refuse"
    }

    private var passwords: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line("Your passwords", "In the macOS keychain, shown with Touch ID") {
                    Pill("Open…") {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
                Rule()
                Line("Offer to save passwords", savingDetail) {
                    Switch(on: $prefs.savesPasswords)
                }
                Rule()
                Line("Fill in sign-ins", "Click a sign-in box and the accounts kept for the site hang from it") {
                    Switch(on: $prefs.fillsPasswords)
                }
                Rule()
                Line(
                    "Offer passkeys",
                    !prefs.passkeysPossible
                        ? "Needs an Apple entitlement this build doesn't have — off keeps sites to the password"
                        : Passkeys.access == .denied
                        ? "macOS was told no — System Settings › Privacy & Security › Passkeys Access for Web Browsers"
                        : "Touch ID or an iCloud passkey, on sites that offer one"
                ) {
                    Switch(on: $prefs.passkeys)
                }
                if !Vault.never.isEmpty {
                    Rule()
                    Line("Sites never asked", "\(Vault.never.count) sites told to stop offering") {
                        Pill("Forget") {
                            Vault.never = []
                            browser.announce("Every site can ask again")
                        }
                    }
                }
            }
            Card {
                Line("Bring yours in", "From Dia, Chrome, Arc, Brave or Edge on this Mac — nothing leaves it") {
                    Pill("Import…") {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
            }
        }
    }

    // MARK: - downloads

    private var downloads: some View {
        Card {
            Line("Save to", prefs.downloads.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                Pill("Change…") { chooseFolder() }
            }
            Rule()
            Line("Ask where to save each file") {
                Switch(on: $prefs.asksWhereToSave)
            }
        }
    }

    // MARK: - privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line("Block ads and trackers", shield.trouble ?? "Third parties whose only job is to watch") {
                    Switch(on: $prefs.shielded)
                }
                if let trouble = shield.trouble {
                    Rule()
                    Line(trouble, "Nothing is being blocked until this clears — try again, or restart Search") {
                        Pill("Try again") { shield.compile() }
                    }
                }
                if let host = browser.hereHost, prefs.shielded, shield.trouble == nil {
                    Rule()
                    Line("Block on \(host)", "Turn off here if the site breaks — the page reloads") {
                        Switch(on: Binding(
                            get: { !Shield.shared.isPaused(on: host) },
                            set: { on in
                                Shield.shared.pause(host, !on)
                                browser.reload()
                            }
                        ))
                    }
                }
                Rule()
                Line("Camera and microphone", "What each site was allowed or refused") {
                    Pill("Forget choices") { browser.forgetCaptureChoices() }
                }
            }
            Card {
                Line("History", "Every address you have been to") {
                    Pill("Clear") { browser.clearHistory() }
                }
                Rule()
                Line("Cookies and sign-ins", "Signs you out of every site") {
                    Pill("Sign out of everything") { browser.clearSites() }
                }
                Rule()
                Line("Cache", "Only what was fetched to draw pages") {
                    Pill("Clear") { browser.clearCache() }
                }
            }
        }
    }

    // MARK: - about

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Logomark()
                    .fill(Palette.ink, style: FillStyle(eoFill: true))
                    .aspectRatio(Logomark.canvas.width / Logomark.canvas.height, contentMode: .fit)
                    .frame(height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Search")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("by Office Commun · version \(Updater.version)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.bottom, 2)

            Card {
                Line(versionTitle, versionDetail) { versionControl }
                Rule()
                Line("Install updates on its own", "Off, Search still looks once a day and tells you, and installs only when you press Install") {
                    Switch(on: $prefs.installsUpdates)
                }
                Rule()
                Line("Found something wrong?", "Opens a draft with the version already in it") {
                    Pill("Send Feedback") { Links.writeFeedback() }
                }
            }

            Card {
                Shortcut("⌘L", "Address")
                Rule()
                Shortcut("⌘K", "Switch tab")
                Rule()
                Shortcut("⌘T  ⌘W  ⇧⌘T", "New, close, reopen tab")
                Rule()
                Shortcut("⇧⌘V", "Paste and go")
                Rule()
                Shortcut("⇧⌘C", "Copy address")
                Rule()
                Shortcut("⌃⇥  ⌘1–9", "Next tab, a tab by its place")
                Rule()
                Shortcut("⇧⌘S", "Tabs in a sidebar")
                Rule()
                Shortcut("⌘S", "Fold the sidebar away")
                Rule()
                Shortcut("⇧⌘R", "Reading mode")
                Rule()
                Shortcut("⇧⌘H", "Hide something on this site")
                Rule()
                Shortcut("⇧⌘P", "Float the video")
            }
        }
    }

    /// The version line follows the newer build from found to fetched to
    /// in place; with none, it is simply this one.
    private var versionTitle: String {
        switch updater.stage {
        case .none: return "Updates"
        case .fetching(let next): return "Search \(next.version) is downloading…"
        case .ready(let next): return "Search \(next.version) is ready"
        case .offered(let next), .waiting(let next): return "Search \(next.version) is out"
        }
    }

    private var versionDetail: String {
        switch updater.stage {
        case .none:
            return updater.lastChecked.map { "Checked \($0.formatted(.relative(presentation: .named))) — once a day on its own" }
                ?? "Checked once a day on its own"
        case .fetching(let next):
            return next.notes ?? "Quietly, in the background — nothing you have set is touched"
        case .ready(let next):
            return next.notes ?? "It's there the next time you open Search"
        case .offered(let next):
            return next.notes ?? "Open the disk image, the same as the first time"
        case .waiting(let next):
            return next.notes ?? "Checked and put in place when you press Install"
        }
    }

    @ViewBuilder
    private var versionControl: some View {
        switch updater.stage {
        case .none:
            Pill(updater.checking ? "Checking…" : "Check now") {
                updater.check { found in
                    if found == nil { browser.announce("This is the latest one") }
                }
            }
            .disabled(updater.checking)
        case .fetching:
            Ring(size: 12)
        case .ready:
            Pill("Relaunch now", filled: true) { updater.relaunch() }
        case .offered(let next):
            Pill("Download", filled: true) {
                browser.tuning = false
                browser.open(next.dmg, foreground: true)
            }
        case .waiting:
            Pill("Install", filled: true) { updater.install() }
        }
    }

    // MARK: - doing

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.downloads
        panel.prompt = "Use this folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.downloads = url
    }

    // MARK: - pieces

    /// A keystroke and what it does.
    private struct Shortcut: View {
        let keys: String
        let does: String
        init(_ keys: String, _ does: String) { self.keys = keys; self.does = does }

        var body: some View {
            HStack {
                Text(does)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(keys)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

/// A row of choices in a grey track, one of them lifted out in white. The
/// white slides to the one you pick rather than appearing there.
struct Segmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    /// True when the control has the whole width to itself, so the choices
    /// share it evenly instead of each taking only what its word needs.
    var wide = false

    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                Text(title)
                    .font(.system(size: 11.5, weight: option == selection ? .medium : .regular))
                    .foregroundStyle(option == selection ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: !wide, vertical: false)
                    .frame(maxWidth: wide ? .infinity : nil)
                    .padding(.horizontal, wide ? 4 : 10)
                    .padding(.vertical, 5)
                    .background {
                        if option == selection {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.ground)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "chosen", in: slide)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onTapGesture {
                        withAnimation(Motion.settle) { selection = option }
                    }
            }
        }
        .padding(2)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(Motion.settle, value: selection)
    }
}

/// On or off, in ink rather than in blue.
struct Switch: View {
    @Binding var on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Palette.ink : Palette.faint)
            .frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(Palette.ground)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(Motion.settle) { on.toggle() } }
            .animation(Motion.settle, value: on)
    }
}

/// A small capsule that does one thing. Outlined by default; filled in ink
/// when it is the thing you came here to press.
struct Pill: View {
    let title: String
    var filled = false
    var tint: Color = Palette.ink
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, filled: Bool = false, tint: Color = Palette.ink, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(filled ? Palette.ground : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.ground), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
