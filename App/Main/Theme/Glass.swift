import SwiftUI

// Liquid Glass, as declared in the macOS 26 SDK (SwiftUICore.swiftinterface):
//   func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View
//   Glass.regular / .clear, Glass.tint(_ color: Color?), Glass.interactive(_:)

/// The launcher's own measures, from its approved design mockup, on the shared tokens.
enum Theme {
    static let panelWidth: CGFloat = 680
    static let rowHeight: CGFloat = 44
    static let sectionHeaderHeight: CGFloat = 24
    static let keyCapSize: CGFloat = 20
    /// The launcher's query and its rows.
    static let queryRole = TextRole.hero
    static let rowRole = TextRole.emphasis

    /// Development aid: draw glass as its solid stand-in, so a window can be drawn into a picture.
    #if TOOLSMITH_DEV
    static let solidGlass = CommandLine.arguments.contains { $0.hasPrefix("--snapshot") }
    #else
    static let solidGlass = false
    #endif

    static let appear: Double = 0.16
    static let disappear: Double = 0.10
}

/// The dark glass every surface of the app sits on.
struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var corner: CGFloat = Radius.xl

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Group {
            if reduceTransparency || Theme.solidGlass {
                content.background(Surface.ground, in: shape)
            } else {
                content.glassEffect(.regular.tint(Surface.ground.opacity(0.62)), in: shape)
            }
        }
        .overlay(shape.strokeBorder(Line.base, lineWidth: 1))
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }
}

extension View {
    func glassSurface(corner: CGFloat = Radius.xl) -> some View { modifier(GlassSurface(corner: corner)) }
}
