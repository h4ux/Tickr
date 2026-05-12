import Foundation
import AppKit

enum ClipboardItemType: String, Codable {
    case text
    case image
    case file
}

struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    /// Display label. For text — the content itself; for images — "WxH PNG";
    /// for files — the filename.
    let text: String
    /// PNG bytes — image content (type == .image) or Quick Look thumbnail (type == .file).
    let imageData: Data?
    /// Absolute path of the source file (type == .file only).
    let filePath: String?
    let timestamp: Date

    init(id: UUID = UUID(), type: ClipboardItemType, text: String, imageData: Data? = nil, filePath: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.text = text
        self.imageData = imageData
        self.filePath = filePath
        self.timestamp = timestamp
    }

    /// Short label shown in the history list.
    var preview: String {
        switch type {
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(empty)" : trimmed
        case .image:
            return text
        case .file:
            return text  // filename
        }
    }

    /// Approximate match for search.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return text.range(of: query, options: .caseInsensitive) != nil
    }

    /// Push this item back onto `NSPasteboard.general` so the user can paste it.
    func writeToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch type {
        case .text:
            pb.setString(text, forType: .string)
        case .image:
            if let data = imageData, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        case .file:
            if let path = filePath {
                let url = URL(fileURLWithPath: path)
                pb.writeObjects([url as NSURL])
            }
        }
    }
}
