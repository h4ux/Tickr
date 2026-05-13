import Foundation
import AppKit
import Combine
import QuickLookThumbnailing

class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    @Published var items: [ClipboardItem] = []

    private let settings = AppSettings.shared
    private var lastChangeCount: Int = 0
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private static let persistKey = "clipboardHistoryItems"

    private init() {
        loadFromDisk()
        lastChangeCount = NSPasteboard.general.changeCount

        // React to the toggle in settings
        settings.$clipboardEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled { self?.start() } else { self?.stop() }
            }
            .store(in: &cancellables)

        // React to history-size changes
        settings.$clipboardHistoryLimit
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.trimHistory() }
            .store(in: &cancellables)

        if settings.clipboardEnabled { start() }
    }

    // MARK: - Polling

    private func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        capture(from: pb)
    }

    private func capture(from pb: NSPasteboard) {
        // 1) File URLs (Finder copy of any file: PDF, docx, etc.)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first(where: { $0.isFileURL }) {
            let path = url.path
            // Skip duplicate of most-recent file
            if let last = items.first, last.type == .file, last.filePath == path { return }
            captureFile(at: url)
            return
        }

        // 2) Pasteboard image bytes
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = images.first,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {

            let label = "\(Int(img.size.width))×\(Int(img.size.height)) PNG"
            let item = ClipboardItem(type: .image, text: label, imageData: png)
            prepend(item)
            return
        }

        // 3) Plain text
        if let str = pb.string(forType: .string), !str.isEmpty {
            if let last = items.first, last.type == .text, last.text == str { return }
            let item = ClipboardItem(type: .text, text: str)
            prepend(item)
        }
    }

    private func captureFile(at url: URL) {
        let filename = url.lastPathComponent
        let path = url.path

        // Generate Quick Look thumbnail asynchronously, then store the item.
        let thumbSize = CGSize(width: 512, height: 512)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            DispatchQueue.main.async {
                let pngData: Data? = {
                    guard let rep = rep else { return nil }
                    let img = rep.nsImage
                    guard let tiff = img.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
                    return bitmap.representation(using: .png, properties: [:])
                }()
                let item = ClipboardItem(type: .file, text: filename, imageData: pngData, filePath: path)
                self?.prepend(item)
            }
        }
    }

    private func prepend(_ item: ClipboardItem) {
        var arr = items
        arr.insert(item, at: 0)
        // Cap size
        let limit = max(1, settings.clipboardHistoryLimit)
        if arr.count > limit { arr.removeLast(arr.count - limit) }
        items = arr
        saveToDisk()

        // Push to sync (no-op unless enabled + licensed)
        ClipboardSyncService.shared.pushIfEnabled(item: item)
    }

    private func trimHistory() {
        let limit = max(1, settings.clipboardHistoryLimit)
        if items.count > limit {
            items = Array(items.prefix(limit))
            saveToDisk()
        }
    }

    // MARK: - Actions

    func paste(_ item: ClipboardItem) {
        item.writeToPasteboard()
        // Lift the change-count past our own write so we don't re-capture it.
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Create a new text entry from edited content. The original item is left
    /// alone — the edited version becomes the most-recent item.
    @discardableResult
    func addEditedText(_ text: String) -> ClipboardItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = ClipboardItem(type: .text, text: trimmed)
        prepend(item)
        return item
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        saveToDisk()
        ClipboardSyncService.shared.pushDeletionIfEnabled(itemId: item.id)
    }

    func clearAll() {
        for item in items {
            ClipboardSyncService.shared.pushDeletionIfEnabled(itemId: item.id)
        }
        items = []
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistKey),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.persistKey)
        }
    }
}
