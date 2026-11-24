import AppKit
import Combine
import ToolsmithKit

/// One thing a module shows in the menu bar: how it looks in each of its styles, when it needs
/// drawing again, and what a click does.
struct MenuBarItem {
    let descriptor: MenuBarItemDescriptor
    /// The pieces for a style. nil: nothing to show right now (a battery reading on a Mac without one).
    let glyph: @MainActor (MenuBarStyle) -> MenuBarGlyph?
    /// Fires when the drawing may have changed.
    let changes: AnyPublisher<Void, Never>
    /// A left click; the frame is the item's place on screen, for a panel opened under it.
    let click: @MainActor (NSRect) -> Void
}

/// What an item draws, piece by piece, and what VoiceOver reads for it.
struct MenuBarGlyph {
    var pieces: [MenuBarPiece]
    var spoken: String
}

/// The pieces the renderer knows how to draw. Words and symbols follow the menu bar's appearance;
/// graphs carry their own colors.
enum MenuBarPiece {
    case mark(NSImage)
    /// An SF Symbol at menu bar size.
    case symbol(String)
    /// One line of text.
    case text(String)
    /// A short name written top to bottom.
    case label(String)
    /// Stacked bars: lower part and upper part of each value (0…1).
    case bars(lower: [Double], upper: [Double])
    /// A narrow box filled from the bottom (0…1).
    case level(Double, NSColor)
    /// Bars above a middle line and below it, on one scale (0…1).
    case mirror(above: [Double], below: [Double], aboveColor: NSColor, belowColor: NSColor)
    /// Two short lines, one over the other.
    case stack(String, String)

    /// Pieces drawn in one color only, so the image can be a template the menu bar tints.
    var isMonochrome: Bool {
        switch self {
        case .mark, .symbol, .text, .label, .stack: return true
        case .bars, .level, .mirror: return false
        }
    }
}

extension MenuBarItem {
    /// An item that is only an icon: its module's symbol, and a click.
    static func icon(_ descriptor: MenuBarItemDescriptor, click: @escaping @MainActor (NSRect) -> Void) -> MenuBarItem {
        MenuBarItem(descriptor: descriptor, glyph: { _ in MenuBarGlyph(pieces: [.symbol(descriptor.symbol)], spoken: descriptor.title) },
                    changes: Empty().eraseToAnyPublisher(), click: click)
    }
}
