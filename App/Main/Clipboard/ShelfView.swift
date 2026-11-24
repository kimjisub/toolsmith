import AppKit
import QuickLookThumbnailing
import SwiftUI
import ToolsmithKit

@MainActor final class ShelfPresentation: ObservableObject {
    @Published var isShown = false
    /// Why nothing is being recorded, if so (paused, or macOS does not let us read).
    @Published var banner: String?
}

/// The clipboard history: a bar along the bottom of the screen, newest card first.
struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var presentation: ShelfPresentation
    let store: ClipStore
    var onCommand: (QueryCommand) -> Void
    var onPick: (Int64) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let cardSize = CGSize(width: 232, height: 186)

    var body: some View {
        VStack(spacing: 0) {
            header
            Line.subtle.frame(height: 1)
            if model.items.isEmpty {
                empty
            } else {
                cards
            }
            footer
        }
        .glassSurface(corner: 22)
        .shadow(color: Shade.strong, radius: 30, y: 12)
        .offset(y: presentation.isShown || reduceMotion ? 0 : 26)
        .opacity(presentation.isShown ? 1 : 0)
        .animation(.easeOut(duration: presentation.isShown ? Theme.appear : Theme.disappear), value: presentation.isShown)
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: Space.l) {
            Text("클립보드")
                .font(.role(.secondary, weight: .medium))
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .background(Fill.selected, in: Capsule())
            GradientQueryField(text: $model.query, placeholder: "복사했던 것 찾기", role: .heading, capturesNavigation: true, onCommand: onCommand)
                .frame(maxWidth: 360)
            Spacer(minLength: Space.s)
            HStack(spacing: Space.xs) {
                ForEach(Array(ShelfModel.filters.enumerated()), id: \.offset) { _, filter in
                    chip(filter?.title ?? "전체", selected: model.kind == filter) { model.kind = filter }
                }
                Line.subtle.frame(width: 1, height: 16).padding(.horizontal, Space.s)
                chip("고정한 것", selected: model.pinnedOnly) { model.pinnedOnly.toggle() }
            }
        }
        .padding(.horizontal, Space.l)
        .frame(height: 50)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.role(.secondary))
                .foregroundStyle(selected ? Color.white : Ink.tertiary)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .background(selected ? Fill.selected : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Space.m) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ClipCard(item: item, number: index < 9 ? index + 1 : nil, selected: item.id == model.selectedID, store: store)
                            .id(item.id)
                            .onAppear { model.appeared(item.id) }
                            .onTapGesture(count: 2) { onPick(item.id) }
                            .onTapGesture { model.select(item.id) }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.l)
            }
            .scrollIndicators(.never)
            .frame(height: Self.cardSize.height + 28)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private var empty: some View {
        let searching = !model.query.trimmingCharacters(in: .whitespaces).isEmpty || model.kind != nil || model.pinnedOnly
        return Text(searching ? "찾는 것이 없습니다" : "아직 복사한 것이 없습니다. 무언가를 복사하면 여기에 쌓입니다.")
            .font(.role(.body))
            .foregroundStyle(Ink.tertiary)
            .frame(maxWidth: .infinity)
            .frame(height: Self.cardSize.height + 28)
    }

    private var footer: some View {
        HStack(spacing: Space.xs) {
            if let banner = presentation.banner {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Status.warning)
                Text(banner).foregroundStyle(Status.warning)
            } else if model.lastDeleted != nil {
                KeyCap(label: "⌘"); KeyCap(label: "Z"); Text("지운 것 되돌리기")
            } else {
                KeyCap(label: "↵"); Text("쓰던 앱에 붙여넣기")
                KeyCap(label: "⇧").padding(.leading, Space.m); KeyCap(label: "↵"); Text("서식 없이")
                KeyCap(label: "⌘").padding(.leading, Space.m); KeyCap(label: "1"); Text("~"); KeyCap(label: "9"); Text("바로 붙여넣기")
            }
            Spacer()
            KeyCap(label: "⇥"); Text("종류")
            KeyCap(label: "⌘").padding(.leading, Space.m); KeyCap(label: "P"); Text("고정")
            KeyCap(label: "⌘").padding(.leading, Space.m); KeyCap(label: "⌫"); Text("지우기")
            KeyCap(label: "esc").padding(.leading, Space.m); Text("닫기")
        }
        .font(.role(.detail))
        .foregroundStyle(Ink.tertiary)
        .padding(.horizontal, Space.l)
        .frame(height: 34)
        .background(Shade.soft)
    }
}

/// One copied thing.
struct ClipCard: View {
    let item: ClipItem
    let number: Int?
    let selected: Bool
    let store: ClipStore

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                if let icon = AppIconCache.icon(bundleID: item.sourceBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(item.sourceName ?? item.kind.title).font(.role(.detail, weight: .medium)).foregroundStyle(Ink.secondary).lineLimit(1)
                Spacer(minLength: Space.xs)
                if item.pinned { Image(systemName: "pin.fill").font(.role(.caption)).foregroundStyle(Status.warning) }
                Text(RelativeTime.text(from: item.copiedAt, now: Date())).font(.role(.detail)).foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, Space.m)
            .frame(height: 32)
            .background(Fill.card)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Space.m)
                .clipped()

            HStack(spacing: Space.s) {
                Text(detail).font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(1)
                Spacer(minLength: Space.xs)
                if let number { KeyCap(label: "\(number)", highlighted: selected) }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 30)
        }
        .frame(width: ShelfView.cardSize.width, height: ShelfView.cardSize.height)
        .background(selected ? Fill.selected : Fill.card, in: shape)
        .overlay(shape.strokeBorder(selected ? Tint.light(Brand.glow) : Line.subtle, lineWidth: 1))
        .shadow(color: selected ? Tint.light(Brand.glow) : .clear, radius: 11)
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text:
            Text(String((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)))
                .font(.role(.secondary)).foregroundStyle(Ink.primary).lineSpacing(2)
        case .link:
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(URLComponents(string: (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "링크")
                    .font(.role(.body, weight: .medium)).foregroundStyle(Brand.lavender).lineLimit(1)
                Text(item.text ?? "").font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(4)
            }
        case .image:
            if let url = store.blobURL(for: item), let image = ThumbnailCache.image(at: url) {
                PreviewImage(image: image)
            } else {
                Text("이미지를 찾을 수 없습니다").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
            }
        case .file where FilePreview.previewable(item.fileURLs):
            if item.fileURLs.count == 1 {
                FileThumbnail(path: item.fileURLs[0])
            } else {
                // Several files: the first four, side by side.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)], spacing: Space.s) {
                    ForEach(Array(item.fileURLs.prefix(4).enumerated()), id: \.offset) { _, path in
                        FileThumbnail(path: path).frame(height: 62)
                    }
                }
            }
        case .file:
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(Array(item.fileURLs.prefix(4).enumerated()), id: \.offset) { _, path in
                    HStack(spacing: Space.s) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 16, height: 16)
                        Text((path as NSString).lastPathComponent).font(.role(.secondary)).foregroundStyle(Ink.primary).lineLimit(1).truncationMode(.middle)
                    }
                }
                if item.fileURLs.count > 4 { Text("외 \(item.fileURLs.count - 4)개").font(.role(.detail)).foregroundStyle(Ink.tertiary) }
            }
        }
    }

    private var detail: String {
        switch item.kind {
        case .text: return "\(item.text?.count ?? 0)자"
        case .link: return "링크"
        case .image:
            if let width = item.width, let height = item.height { return "\(width) × \(height) · \(ByteSize.text(item.bytes))" }
            return ByteSize.text(item.bytes)
        case .file:
            guard item.fileURLs.count == 1, let path = item.fileURLs.first else { return "파일 \(item.fileURLs.count)개" }
            let name = (path as NSString).lastPathComponent
            if let size = FilePreview.pixelSize(path) { return "\(size.width) × \(size.height) · \(name)" }
            return name
        }
    }
}

/// App icons by bundle id, looked up once.
@MainActor enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID, !missing.contains(bundleID) else { return nil }
        if let icon = icons[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}

/// Small versions of stored images, so scrolling the shelf never decodes a full screenshot.
@MainActor enum ThumbnailCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width / 2, height: thumbnail.height / 2))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// An image filling the card, on a checkerboard so transparent parts read as transparent.
private struct PreviewImage: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image).resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Checkerboard())
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 7
            for row in 0..<Int(ceil(size.height / side)) {
                for column in 0..<Int(ceil(size.width / side)) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)), with: .color(Fill.card))
                }
            }
        }
        .background(Shade.medium)
    }
}

/// A copied file shown as itself: Quick Look's picture of it (images, videos, PDFs, documents),
/// or its icon and name when there is no picture or the file is gone.
private struct FileThumbnail: View {
    let path: String
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                PreviewImage(image: image)
            } else if failed {
                VStack(spacing: Space.s) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 34, height: 34)
                    Text((path as NSString).lastPathComponent).font(.role(.detail)).foregroundStyle(Ink.secondary).lineLimit(2).truncationMode(.middle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Fill.faint.clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            }
        }
        .task(id: path) {
            if let cached = FilePreview.cached(path) {
                image = cached
                return
            }
            image = await FilePreview.thumbnail(path)
            failed = image == nil
        }
    }
}

/// Pictures and pixel sizes of copied files, made once per file version.
@MainActor enum FilePreview {
    private static let cache = NSCache<NSString, NSImage>()
    private static var sizes: [String: (width: Int, height: Int)?] = [:]

    /// Whether the files are worth a picture: they exist and at least one is not a folder.
    static func previewable(_ paths: [String]) -> Bool {
        paths.contains { path in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder.boolValue
        }
    }

    private static func key(_ path: String) -> NSString {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(path)#\(modified)" as NSString
    }

    static func cached(_ path: String) -> NSImage? { cache.object(forKey: key(path)) }

    static func thumbnail(_ path: String) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: 240, height: 160),
                                                   scale: 2, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: key(path))
        return image
    }

    /// An image file's size in pixels, read from its header; nil for anything else.
    static func pixelSize(_ path: String) -> (width: Int, height: Int)? {
        if let known = sizes[path] { return known }
        var size: (width: Int, height: Int)?
        if let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            size = (width, height)
        }
        sizes[path] = size
        return size
    }
}
