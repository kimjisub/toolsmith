import Foundation

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, link, image, file

    public var title: String {
        switch self {
        case .text: return "글"
        case .link: return "링크"
        case .image: return "이미지"
        case .file: return "파일"
        }
    }
}

/// Something just copied, before it is stored.
public struct ClipDraft {
    public let kind: ClipKind
    /// The copied text (text and link kinds).
    public let text: String?
    /// The image bytes (image kind), or the formatted form of the text (RTF) for text kinds.
    public let data: Data?
    /// Paths of the copied files (file kind).
    public let fileURLs: [String]
    public let sourceBundleID: String?
    public let sourceName: String?
    public let width: Int?
    public let height: Int?

    public init(kind: ClipKind, text: String?, data: Data?, fileURLs: [String], sourceBundleID: String?, sourceName: String?, width: Int?, height: Int?) {
        self.kind = kind
        self.text = text
        self.data = data
        self.fileURLs = fileURLs
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.width = width
        self.height = height
    }
}

/// One entry of the clipboard history.
public struct ClipItem: Identifiable, Equatable {
    public let id: Int64
    public let kind: ClipKind
    public let text: String?
    public let fileURLs: [String]
    /// File name, under the store's `blobs` folder, of the stored image or of a text's formatted form.
    public let blobName: String?
    public let bytes: Int
    public let width: Int?
    public let height: Int?
    public let sourceBundleID: String?
    public let sourceName: String?
    public let copiedAt: Date
    public var pinned: Bool
    /// Identifies the content, so copying the same thing again does not add a second entry.
    public let hash: String
}

/// How long history is kept. Pinned items are kept regardless.
public enum ClipRetention: String, Codable, CaseIterable, Sendable {
    case forever, year, days90, days30

    public var title: String {
        switch self {
        case .forever: return "영구"
        case .year: return "1년"
        case .days90: return "90일"
        case .days30: return "30일"
        }
    }

    /// Items copied before this moment are removed. nil keeps everything.
    public func cutoff(now: Date) -> Date? {
        switch self {
        case .forever: return nil
        case .year: return now.addingTimeInterval(-365 * 86_400)
        case .days90: return now.addingTimeInterval(-90 * 86_400)
        case .days30: return now.addingTimeInterval(-30 * 86_400)
        }
    }
}
