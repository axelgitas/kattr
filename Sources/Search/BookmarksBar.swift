import SwiftUI

// The bookmarks bar: the top of the bookmarks, in a thin row above the page,
// as Chrome and Safari have one. A folder opens as a menu. More than the row
// holds scrolls sideways.
//
// Off unless asked for — Settings › Tabs, or Bookmarks › Show Bookmarks Bar
// — since the page gives up a strip of its height to it. It goes with the
// tabs when they fold away (⌘S) and when a video takes the screen.

struct BookmarksBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks
    @ObservedObject private var paletteUpdates = AppearancePaletteUpdates.shared
    @ObservedObject private var legibility = ChromeLegibility.shared
    @Environment(\.colorScheme) private var colorScheme

    static let height: CGFloat = 30

    var body: some View {
        let _ = paletteUpdates.revision
        let isArtwork = ChromeLegibility.isChromeArtworkVisiblyActive(for: browser)
        let chrome = legibility.foreground(for: browser, isSidebar: false, colorScheme: colorScheme)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(bookmarks.roots) { node in
                    Item(node: node, chrome: chrome, isArtwork: isArtwork) {
                        if node.isFolder {
                            BookmarkMenu.shared.popUp(node)
                        } else if let text = node.url, let url = URL(string: text) {
                            browser.visit(url)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: BookmarksBar.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isArtwork ? Color.clear : Palette.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(isArtwork ? chrome.hairline : Palette.hairline).frame(height: 1)
        }
    }

    private struct Item: View {
        let node: Bookmark
        let chrome: ChromeForeground
        let isArtwork: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 6) {
                if node.isFolder {
                    Image(systemName: "folder")
                        .font(.system(size: 10.5))
                        .foregroundStyle(isArtwork ? chrome.muted : Palette.muted)
                        .chromeContrastHalo(chrome)
                } else {
                    Mark(icon: Favicons.shared.cached(node.host ?? ""), letter: String((node.host ?? "•").prefix(1)).uppercased(), size: 13)
                }
                Text(node.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isArtwork ? chrome.ink : Palette.ink)
                    .chromeContrastHalo(chrome)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                if node.isFolder {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(isArtwork ? chrome.faint : Palette.faint)
                        .chromeContrastHalo(chrome)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? (isArtwork ? chrome.hover : Palette.hover) : .clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: act)
            .onHover { hovering = $0 }
            .help(node.url ?? node.title)
        }
    }
}
