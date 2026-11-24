import XCTest
@testable import ToolsmithKit

/// The palette's contrast promises (WCAG 2.1): reading text 4.5:1, everything else 3:1.
final class PaletteTests: XCTestCase {
    private func contrast(_ text: RGBA, on surface: RGBA) -> Double {
        RGBA.contrast(text.over(surface), surface)
    }

    func testReadingTextStaysReadableOnEverySurface() {
        for (name, text) in [("primary", Palette.Text.primary), ("secondary", Palette.Text.secondary), ("tertiary", Palette.Text.tertiary)] {
            for surface in Palette.readingSurfaces {
                XCTAssertGreaterThanOrEqual(contrast(text, on: surface), 4.5, "\(name) text")
            }
        }
    }

    func testDisabledTextIsAtLeastNonTextContrast() {
        for surface in Palette.readingSurfaces {
            XCTAssertGreaterThanOrEqual(contrast(Palette.Text.disabled, on: surface), 3)
        }
    }

    func testBrandAndStatusColorsReadAsTextOnGroundAndCards() {
        let colors = [("lavender", Palette.lavender), ("peach", Palette.peach), ("glow", Palette.glow), ("mint", Palette.mint),
                      ("success", Palette.success), ("warning", Palette.warning), ("danger", Palette.danger), ("info", Palette.info)]
        for (name, color) in colors {
            for surface in Palette.readingSurfaces.prefix(2) {
                XCTAssertGreaterThanOrEqual(contrast(color, on: surface), 4.5, name)
            }
            XCTAssertGreaterThanOrEqual(contrast(color, on: Palette.readingSurfaces[2]), 3, "\(name) on a selected row")
        }
    }

    func testWhiteSymbolsReadOnEveryTile() {
        for tile in Palette.Tile.all {
            XCTAssertGreaterThanOrEqual(RGBA.contrast(.white(1), tile), 3)
        }
    }

    func testTextOnAccentIsReadable() {
        XCTAssertGreaterThanOrEqual(RGBA.contrast(Palette.inkText, Palette.lavender), 4.5)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(Palette.inkText, .white(1)), 4.5)
    }

    func testContrastMath() {
        XCTAssertEqual(RGBA.contrast(.white(1), .black(1)), 21, accuracy: 0.01)
        XCTAssertEqual(RGBA.contrast(.white(1), .white(1)), 1, accuracy: 0.001)
        XCTAssertEqual(RGBA.white(0.5).over(.black(1)).r, 0.5, accuracy: 0.0001)
    }
}
