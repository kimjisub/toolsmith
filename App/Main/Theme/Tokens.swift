import SwiftUI
import ToolsmithKit

// The design tokens. Screens use these names only; `scripts/lint-design.sh` refuses numbers and
// colors written directly in a view. Colors come from the palette (`Palette`, in the framework,
// where their contrast is tested); here they get the names of what they are for.

// MARK: Type

/// What a piece of text is. Sizes are whole points on one scale (10, 11, 12, 13, 15, 17, 20, 24,
/// 32, after the macOS type sizes); each role has its size, weight and line height.
enum TextRole: CaseIterable {
    /// Letters inside small graphics: chart axes, badges, footnote numbers.
    case caption
    /// Explanations under a row, notes under a group, panel labels.
    case detail
    /// Secondary lines in lists and panels, buttons in rows, subtitles.
    case secondary
    /// Row titles and ordinary text.
    case body
    /// Launcher rows, panel titles.
    case emphasis
    /// Module headers, dialog titles.
    case heading
    /// Page titles.
    case title
    /// The launcher's query, the app's name on the about page.
    case hero
    /// Big figures (a reading, a total).
    case figure

    var size: CGFloat {
        switch self {
        case .caption: return 10
        case .detail: return 11
        case .secondary: return 12
        case .body: return 13
        case .emphasis: return 15
        case .heading: return 17
        case .title: return 20
        case .hero: return 24
        case .figure: return 32
        }
    }

    /// The role's own weight; a call can make it heavier for emphasis.
    var weight: Font.Weight {
        switch self {
        case .heading, .title: return .semibold
        case .figure: return .light
        default: return .regular
        }
    }

    /// The distance from one line's baseline to the next.
    var lineHeight: CGFloat {
        switch self {
        case .caption: return 12
        case .detail: return 16
        case .secondary: return 16
        case .body: return 20
        case .emphasis: return 20
        case .heading: return 24
        case .title: return 24
        case .hero: return 32
        case .figure: return 40
        }
    }

    var label: String {
        switch self {
        case .caption: return "caption"
        case .detail: return "detail"
        case .secondary: return "secondary"
        case .body: return "body"
        case .emphasis: return "emphasis"
        case .heading: return "heading"
        case .title: return "title"
        case .hero: return "hero"
        case .figure: return "figure"
        }
    }
}

extension Font {
    /// The font of a text role. `weight` makes it heavier for emphasis; `design` is for numbers
    /// (`.monospaced`, `.rounded`).
    static func role(_ role: TextRole, weight: Font.Weight? = nil, design: Font.Design = .default) -> Font {
        .system(size: role.size, weight: weight ?? role.weight, design: design)
    }
}

extension View {
    /// The font and line height of a text role, for text that may wrap.
    func textRole(_ role: TextRole, weight: Font.Weight? = nil) -> some View {
        font(.role(role, weight: weight)).lineSpacing(max(role.lineHeight - role.size * 1.2, 0))
    }
}

extension NSFont {
    /// The AppKit font of a text role, for measuring and for AppKit fields.
    static func role(_ role: TextRole, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: role.size, weight: weight)
    }
}

// MARK: Color

extension Color {
    init(_ rgba: RGBA) { self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a) }
}

extension NSColor {
    convenience init(_ rgba: RGBA) { self.init(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a) }
}

/// Text and symbols, strongest first.
enum Ink {
    static let primary = Color(Palette.Text.primary)
    static let secondary = Color(Palette.Text.secondary)
    static let tertiary = Color(Palette.Text.tertiary)
    /// Disabled controls and decorations (drag handles, chevrons); never text to be read.
    static let disabled = Color(Palette.Text.disabled)
    /// Text on an accent or white fill.
    static let onAccent = Color(Palette.inkText)
}

/// Fills on glass, faintest first.
enum Fill {
    /// Hovered rows.
    static let faint = Color(Palette.Neutral.n03)
    /// Cards and groups.
    static let card = Color(Palette.Neutral.n05)
    /// Controls, key caps, bar tracks.
    static let control = Color(Palette.Neutral.n08)
    /// Selected rows, pressed buttons.
    static let selected = Color(Palette.Neutral.n12)
}

/// Lines: separators, edges, outlines.
enum Line {
    /// Separators between rows, the edge of a card.
    static let subtle = Color(Palette.Neutral.n08)
    /// The edge of a glass surface, a divider between areas.
    static let base = Color(Palette.Neutral.n16)
    /// Dashed outlines, the edge of something lit.
    static let strong = Color(Palette.Neutral.n24)
}

/// Black over glass, to set a band apart.
enum Shade {
    static let soft = Color(Palette.Shade.s12)
    static let medium = Color(Palette.Shade.s24)
    static let strong = Color(Palette.Shade.s56)
    /// Drop shadows under floating cards.
    static let shadow = Color(Palette.Shade.s56)
}

/// Opaque grounds, for what is not glass.
enum Surface {
    static let ground = Color(Palette.ink)
    static let deep = Color(Palette.inkDeep)
    static let deepCard = Color(Palette.inkRaised)
    static let chip = Color(Palette.graphite)
    static let canvas = Color(Palette.canvas)
    static let canvasBar = Color(Palette.canvasBar)
    static let menuBarTop = Color(Palette.menuBarTop)
    static let menuBarBottom = Color(Palette.menuBarBottom)
}

/// The brand's colors: the accent and the data series.
enum Brand {
    /// The accent: switches that are on, selections, the first data series.
    static let accent = Color(Palette.lavender)
    static let lavender = Color(Palette.lavender)
    static let peach = Color(Palette.peach)
    /// The light around a selected row.
    static let glow = Color(Palette.glow)
    /// The third data series.
    static let mint = Color(Palette.mint)
    static let gradient = LinearGradient(colors: [lavender, peach], startPoint: .leading, endPoint: .trailing)
}

/// A color laid thinly over glass: the ground of a notice or a badge, and its edge.
enum Tint {
    static func wash(_ color: Color) -> Color { color.opacity(0.12) }
    static func edge(_ color: Color) -> Color { color.opacity(0.28) }
    /// The light of a lit (selected, showing) block.
    static func light(_ color: Color) -> Color { color.opacity(0.56) }
    /// Nearly the color: a fill that should still let the glass show.
    static func strong(_ color: Color) -> Color { color.opacity(0.84) }
}

/// Colors that say how something went.
enum Status {
    static let success = Color(Palette.success)
    static let warning = Color(Palette.warning)
    static let danger = Color(Palette.danger)
    static let info = Color(Palette.info)
}

/// The colored squares behind white symbols. Features, settings pages and permissions pick one.
enum Tile {
    static let gray = Color(Palette.Tile.gray)
    static let blue = Color(Palette.Tile.blue)
    static let green = Color(Palette.Tile.green)
    static let teal = Color(Palette.Tile.teal)
    static let indigo = Color(Palette.Tile.indigo)
    static let purple = Color(Palette.Tile.purple)
    static let pink = Color(Palette.Tile.pink)
    static let orange = Color(Palette.Tile.orange)
}

// MARK: Space and shape

/// Spacing, on a 4-point grid.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
}

/// Corner radii, on the same grid.
enum Radius {
    /// Bars, key caps, chips.
    static let xs: CGFloat = 4
    /// Rows, fields, small buttons.
    static let s: CGFloat = 8
    /// Cards and groups.
    static let m: CGFloat = 12
    /// Panels.
    static let l: CGFloat = 16
    /// Windows and the launcher.
    static let xl: CGFloat = 20
}

/// Icon sizes.
enum IconSize {
    /// An app icon in a list.
    static let app: CGFloat = 20
    /// A tile in a list row or the sidebar.
    static let tile: CGFloat = 24
    /// A tile that leads a card row (features, permissions).
    static let tileLarge: CGFloat = 32
    /// The tile of a page header.
    static let header: CGFloat = 40
}
