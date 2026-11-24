#if TOOLSMITH_DEV
import AppKit
import SwiftUI
import ToolsmithKit

/// Development aid: every design token on one sheet (`--render-tokens <png>`), drawn by the app
/// itself, for the contributor guide. Contrast ratios are computed from the palette's numbers.
struct TokenSheet: View {
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: Space.m, alignment: .topLeading)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Design Tokens").font(.role(.title))
                Text("App/Main/Theme/Tokens.swift and App/Kit/Design/Palette.swift. Screens use only these names; the lint rejects any other value. Dark only.")
                    .textRole(.detail).foregroundStyle(Ink.tertiary)
            }
            section(String(localized: "Type Roles")) {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(TextRole.allCases, id: \.self) { role in
                        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                            Text(verbatim: ".\(role.label)").font(.role(.secondary, design: .monospaced)).foregroundStyle(Ink.tertiary).frame(width: 96, alignment: .leading)
                            Text(verbatim: "\(Int(role.size))/\(Int(role.lineHeight))").font(.role(.secondary, design: .monospaced)).foregroundStyle(Ink.tertiary).frame(width: 56, alignment: .leading)
                            Text("The quick brown fox Aa 123").font(.role(role))
                        }
                    }
                }
            }
            section(String(localized: "Text colors (contrast: ground / card / selected row)")) {
                VStack(alignment: .leading, spacing: Space.s) {
                    contrastRow("Ink.primary", Ink.primary, Palette.Text.primary)
                    contrastRow("Ink.secondary", Ink.secondary, Palette.Text.secondary)
                    contrastRow("Ink.tertiary", Ink.tertiary, Palette.Text.tertiary)
                    contrastRow(String(localized: "Ink.disabled (not for reading)"), Ink.disabled, Palette.Text.disabled)
                    contrastRow("Brand.accent", Brand.accent, Palette.lavender)
                    contrastRow("Status.success", Status.success, Palette.success)
                    contrastRow("Status.warning", Status.warning, Palette.warning)
                    contrastRow("Status.danger", Status.danger, Palette.danger)
                    contrastRow("Status.info", Status.info, Palette.info)
                }
            }
            section(String(localized: "Fills and Lines")) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.m) {
                    swatch("Fill.faint", Fill.faint)
                    swatch("Fill.card", Fill.card)
                    swatch("Fill.control", Fill.control)
                    swatch("Fill.selected", Fill.selected)
                    swatch("Line.subtle", Line.subtle, line: true)
                    swatch("Line.base", Line.base, line: true)
                    swatch("Line.strong", Line.strong, line: true)
                    swatch("Shade.soft", Shade.soft)
                    swatch("Shade.medium", Shade.medium)
                    swatch("Shade.strong", Shade.strong)
                    swatch("Surface.ground", Surface.ground)
                    swatch("Surface.deep", Surface.deep)
                    swatch("Surface.chip", Surface.chip)
                    swatch("Surface.canvas", Surface.canvas)
                }
            }
            section(String(localized: "Brand and Status")) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.m) {
                    swatch("Brand.lavender", Brand.lavender)
                    swatch("Brand.peach", Brand.peach)
                    swatch("Brand.glow", Brand.glow)
                    swatch("Brand.mint", Brand.mint)
                    swatch("Status.success", Status.success)
                    swatch("Status.danger", Status.danger)
                }
            }
            section(String(localized: "Tiles (Contrast with White Symbols)")) {
                HStack(spacing: Space.l) {
                    ForEach(Array(zip(["gray", "blue", "green", "teal", "indigo", "purple", "pink", "orange"], Palette.Tile.all)), id: \.0) { name, rgba in
                        VStack(spacing: Space.xs) {
                            IconTile(symbol: "star.fill", color: Color(rgba), size: IconSize.tileLarge)
                            Text(verbatim: "Tile.\(name)").font(.role(.caption, design: .monospaced)).foregroundStyle(Ink.tertiary)
                            Text(String(format: "%.1f:1", RGBA.contrast(.white(1), rgba))).font(.role(.caption, design: .monospaced)).foregroundStyle(Ink.secondary)
                        }
                    }
                }
            }
            section(String(localized: "Spacing: Space (4-pt Grid)")) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach([("xs", Space.xs), ("s", Space.s), ("m", Space.m), ("l", Space.l), ("xl", Space.xl), ("xxl", Space.xxl), ("xxxl", Space.xxxl), ("huge", Space.huge)], id: \.0) { name, value in
                        HStack(spacing: Space.m) {
                            Text(verbatim: "Space.\(name)").font(.role(.secondary, design: .monospaced)).foregroundStyle(Ink.tertiary).frame(width: 110, alignment: .leading)
                            Text(verbatim: "\(Int(value))").font(.role(.secondary, design: .monospaced)).frame(width: 28, alignment: .trailing)
                            Brand.accent.frame(width: value * 4, height: Space.s)
                        }
                    }
                }
            }
            section(String(localized: "Corners: Radius, and Icons: IconSize")) {
                HStack(alignment: .bottom, spacing: Space.xl) {
                    ForEach([("xs", Radius.xs), ("s", Radius.s), ("m", Radius.m), ("l", Radius.l), ("xl", Radius.xl)], id: \.0) { name, value in
                        VStack(spacing: Space.xs) {
                            RoundedRectangle(cornerRadius: value, style: .continuous).fill(Fill.selected)
                                .overlay(RoundedRectangle(cornerRadius: value, style: .continuous).strokeBorder(Line.strong, lineWidth: 1))
                                .frame(width: 56, height: 56)
                            Text(verbatim: "Radius.\(name) \(Int(value))").font(.role(.caption, design: .monospaced)).foregroundStyle(Ink.tertiary)
                        }
                    }
                    ForEach([("app", IconSize.app), ("tile", IconSize.tile), ("tileLarge", IconSize.tileLarge), ("header", IconSize.header)], id: \.0) { name, value in
                        VStack(spacing: Space.xs) {
                            IconTile(symbol: "bolt.fill", color: Tile.indigo, size: value)
                            Text(verbatim: "\(name) \(Int(value))").font(.role(.caption, design: .monospaced)).foregroundStyle(Ink.tertiary)
                        }
                    }
                }
            }
        }
        .padding(Space.xxxl)
        .frame(width: 1080, alignment: .leading)
        .background(Surface.ground)
        .foregroundStyle(Ink.primary)
        .environment(\.colorScheme, .dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title).font(.role(.heading))
            Card(padding: Space.l) { content() }
        }
    }

    private func swatch(_ name: String, _ color: Color, line: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Group {
                if line {
                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(color, lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(color)
                        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Line.subtle, lineWidth: 1))
                }
            }
            .frame(height: 40)
            Text(name).font(.role(.caption, design: .monospaced)).foregroundStyle(Ink.tertiary)
        }
    }

    private func contrastRow(_ name: String, _ color: Color, _ rgba: RGBA) -> some View {
        HStack(spacing: Space.l) {
            Text(name).font(.role(.secondary, design: .monospaced)).foregroundStyle(color).frame(width: 220, alignment: .leading)
            ForEach(Array(Palette.readingSurfaces.enumerated()), id: \.offset) { _, surface in
                let ratio = RGBA.contrast(rgba.over(surface), surface)
                Text(String(format: "%.1f:1", ratio))
                    .font(.role(.secondary, design: .monospaced))
                    .foregroundStyle(color)
                    .frame(width: 80, height: 28)
                    .background(Color(surface), in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            }
        }
    }

    static func render(to url: URL) {
        let renderer = ImageRenderer(content: TokenSheet())
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
