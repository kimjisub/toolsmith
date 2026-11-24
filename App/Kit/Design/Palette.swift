import Foundation

/// A color as numbers, so the palette can be tested (contrast) without a UI framework.
public struct RGBA: Equatable, Sendable {
    public let r: Double, g: Double, b: Double, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        (self.r, self.g, self.b, self.a) = (r, g, b, a)
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }

    public static func white(_ alpha: Double) -> RGBA { RGBA(1, 1, 1, alpha) }
    public static func black(_ alpha: Double) -> RGBA { RGBA(0, 0, 0, alpha) }

    /// This color laid over an opaque `ground`.
    public func over(_ ground: RGBA) -> RGBA {
        RGBA(r * a + ground.r * (1 - a), g * a + ground.g * (1 - a), b * a + ground.b * (1 - a), 1)
    }

    /// WCAG relative luminance of an opaque color.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG contrast ratio of two opaque colors (1…21).
    public static func contrast(_ x: RGBA, _ y: RGBA) -> Double {
        let (light, dark) = x.luminance > y.luminance ? (x.luminance, y.luminance) : (y.luminance, x.luminance)
        return (light + 0.05) / (dark + 0.05)
    }
}

/// The palette: every color the app may use, as base steps. Screens never use these directly;
/// they use the meaning tokens built on them (`App/Main/Theme/Tokens.swift`).
///
/// The app is dark only. Its surfaces are dark glass (the launcher, panels, the settings window),
/// approved as the look (decision D05); a light variant would be a second design, not a second
/// set of values. Neutrals are therefore white at fixed strengths over the ink ground.
public enum Palette {
    // MARK: Grounds
    /// The tint of every glass surface, and its solid stand-in.
    public static let ink = RGBA(hex: 0x1C1E28)
    /// The darkest ground (the first-run guide).
    public static let inkDeep = RGBA(hex: 0x0B0C0F)
    /// A card on the darkest ground.
    public static let inkRaised = RGBA(hex: 0x17181D)
    /// An opaque chip on a panel.
    public static let graphite = RGBA(hex: 0x2B2B2B)
    /// The annotation editor's canvas and toolbar.
    public static let canvas = RGBA(hex: 0x12141A)
    public static let canvasBar = RGBA(hex: 0x1C1F29)
    /// A drawn menu bar (previews).
    public static let menuBarTop = RGBA(hex: 0x292929)
    public static let menuBarBottom = RGBA(hex: 0x1C1C1C)

    // MARK: Neutral steps: white over the ground, strongest first
    public enum Neutral {
        public static let n94 = RGBA.white(0.94)
        public static let n78 = RGBA.white(0.78)
        public static let n60 = RGBA.white(0.60)
        public static let n40 = RGBA.white(0.40)
        public static let n24 = RGBA.white(0.24)
        public static let n16 = RGBA.white(0.16)
        public static let n12 = RGBA.white(0.12)
        public static let n08 = RGBA.white(0.08)
        public static let n05 = RGBA.white(0.05)
        public static let n03 = RGBA.white(0.03)
    }

    /// Black over glass.
    public enum Shade {
        public static let s12 = RGBA.black(0.12)
        public static let s24 = RGBA.black(0.24)
        public static let s56 = RGBA.black(0.56)
    }

    // MARK: Brand
    public static let lavender = RGBA(hex: 0xC7B8FF)
    public static let peach = RGBA(hex: 0xFFC9A3)
    public static let glow = RGBA(hex: 0xA0B4FF)
    public static let mint = RGBA(hex: 0x8FE6C7)
    /// Text on a light fill (a chosen chip, a pressed key cap).
    public static let inkText = RGBA(hex: 0x14171C)

    // MARK: Status
    public static let success = RGBA(hex: 0x6BDB9E)
    public static let warning = peach
    public static let danger = RGBA(hex: 0xFF8075)
    public static let info = glow

    // MARK: Tiles: the colored squares behind white symbols (features, settings pages, permissions).
    // Deep enough that a white symbol stays readable (3:1 or more).
    public enum Tile {
        public static let gray = RGBA(hex: 0x6E6E78)
        public static let blue = RGBA(hex: 0x1F6FE0)
        public static let green = RGBA(hex: 0x1F8A44)
        public static let teal = RGBA(hex: 0x0F7A86)
        public static let indigo = RGBA(hex: 0x5057D6)
        public static let purple = RGBA(hex: 0x8D46C8)
        public static let pink = RGBA(hex: 0xD3386E)
        public static let orange = RGBA(hex: 0xC45A12)
        public static let all = [gray, blue, green, teal, indigo, purple, pink, orange]
    }

    // MARK: Meaning: what the screens use, by role

    /// Text, strongest first. Each stays readable (4.5:1) on every surface it is drawn on.
    public enum Text {
        public static let primary = Neutral.n94
        public static let secondary = Neutral.n78
        public static let tertiary = Neutral.n60
        /// Not for reading: disabled controls, decorations (3:1 is enough).
        public static let disabled = Neutral.n40
    }

    /// The surfaces text sits on: the glass ground, a card on it, and a selected row in a card.
    public static let readingSurfaces: [RGBA] = [ink, Neutral.n05.over(ink), Neutral.n12.over(Neutral.n05.over(ink))]
}
