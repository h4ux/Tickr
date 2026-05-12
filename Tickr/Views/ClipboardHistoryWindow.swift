import SwiftUI
import AppKit

class ClipboardHistoryWindowController {
    static let shared = ClipboardHistoryWindowController()
    private var window: NSWindow?

    private init() {}

    func toggle() {
        if let w = window, w.isVisible {
            w.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        let preferredSize = NSSize(
            width: max(560, CGFloat(AppSettings.shared.clipboardWindowWidth)),
            height: max(320, CGFloat(AppSettings.shared.clipboardWindowHeight))
        )

        if let w = window {
            w.setContentSize(preferredSize)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: ClipboardHistoryView(onPaste: { [weak self] in
            self?.window?.orderOut(nil)
        }))
        let w = NSPanel(contentViewController: host)
        w.setContentSize(preferredSize)
        w.minSize = NSSize(width: 560, height: 320)
        w.title = "Clipboard History"
        w.styleMask = [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView]
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.level = .floating
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject private var clipboard = ClipboardService.shared
    @State private var search = ""
    @State private var selectedID: UUID?
    @State private var keyMonitor: Any?
    let onPaste: () -> Void

    private var filtered: [ClipboardItem] {
        clipboard.items.filter { $0.matches(search) }
    }

    private var selectedItem: ClipboardItem? {
        guard let id = selectedID else { return nil }
        return filtered.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search clipboard…", text: $search)
                    .textFieldStyle(.plain)
                    .onSubmit { copySelected() }
                if !search.isEmpty {
                    Button(action: { search = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                if ClipboardSyncService.shared.isFetching {
                    ProgressView().scaleEffect(0.5)
                } else if LicenseService.shared.isLicensed && AppSettings.shared.clipboardSyncEnabled {
                    Button(action: { ClipboardSyncService.shared.fetch() }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .help("Pull synced clipboard from other devices")
                }
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Split: list | preview
            HSplitView {
                listPane
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                previewPane
                    .frame(minWidth: 260)
            }

            Divider()
            HStack(spacing: 8) {
                Text("\(filtered.count) of \(clipboard.items.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("⏎ to copy  •  esc to close")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button("Clear All") { clipboard.clearAll() }
                    .font(.caption)
                    .disabled(clipboard.items.isEmpty)
            }
            .padding(8)
        }
        .frame(minWidth: 360, minHeight: 280)
        .onAppear {
            selectedID = filtered.first?.id
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var listPane: some View {
        if filtered.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text(clipboard.items.isEmpty ? "Clipboard history is empty" : "No matches")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(filtered, selection: $selectedID) { item in
                    ClipboardRow(item: item)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { paste(item) }
                        .contextMenu {
                            Button("Copy") { clipboard.paste(item) }
                            Button("Delete", role: .destructive) { clipboard.remove(item) }
                        }
                }
                .listStyle(.inset)
                .onChange(of: selectedID) { newID in
                    // Keep the keyboard-driven selection inside the visible area.
                    guard let id = newID else { return }
                    withAnimation(.linear(duration: 0.08)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let item = selectedItem {
            ClipboardPreview(item: item, onCopy: { paste(item) }, onDelete: { clipboard.remove(item) })
        } else {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "eye")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("Select an item to preview")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53:           // Escape
                onPaste()
                return nil
            case 36, 76:       // Return / Enter
                copySelected()
                return nil
            case 125:          // Down arrow
                moveSelection(by: 1)
                return nil
            case 126:          // Up arrow
                moveSelection(by: -1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func copySelected() {
        guard let id = selectedID, let item = filtered.first(where: { $0.id == id }) else {
            if let first = filtered.first { paste(first) }
            return
        }
        paste(item)
    }

    private func paste(_ item: ClipboardItem) {
        clipboard.paste(item)
        onPaste()
    }

    private func moveSelection(by step: Int) {
        guard !filtered.isEmpty else { return }
        let currentIdx = filtered.firstIndex(where: { $0.id == selectedID }) ?? -1
        let next = max(0, min(filtered.count - 1, currentIdx + step))
        selectedID = filtered[next].id
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 8) {
            switch item.type {
            case .text:
                Image(systemName: "text.alignleft")
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(item.preview)
                    .lineLimit(2)
                    .truncationMode(.tail)
            case .image:
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                if let data = item.imageData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 60, maxHeight: 36)
                        .cornerRadius(3)
                }
                Text(item.text)
                    .foregroundColor(.secondary)
                    .font(.caption)
            case .file:
                Image(systemName: "doc.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                if let data = item.imageData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 36, maxHeight: 36)
                        .cornerRadius(3)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let path = item.filePath {
                        Text(path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
            Text(item.timestamp, formatter: clipboardRowFormatter)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private let clipboardRowFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
}()

// MARK: - Preview pane

struct ClipboardPreview: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            body(for: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var headerIcon: String {
        switch item.type {
        case .text:  return "text.alignleft"
        case .image: return "photo"
        case .file:  return "doc.fill"
        }
    }

    private var headerTitle: String {
        switch item.type {
        case .text:  return "Text"
        case .image: return "Image"
        case .file:  return item.text
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .foregroundColor(.accentColor)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.timestamp, formatter: previewHeaderFormatter)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            metadata
            if item.type == .file, let path = item.filePath {
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy to pasteboard (⏎)")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var metadata: some View {
        switch item.type {
        case .text:
            let lines = item.text.split(separator: "\n").count
            Text("\(item.text.count) chars  •  \(lines) line\(lines == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .image:
            if let data = item.imageData {
                Text(formatPreviewBytes(data.count))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .file:
            if let path = item.filePath {
                let attrs = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
                if let size = attrs[.size] as? NSNumber {
                    Text(formatPreviewBytes(size.intValue))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func body(for item: ClipboardItem) -> some View {
        switch item.type {
        case .text:
            ScrollView {
                Text(item.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        case .image:
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                ScrollView([.vertical, .horizontal]) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Couldn't render image data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        case .file:
            filePreview(item: item)
        }
    }

    @ViewBuilder
    private func filePreview(item: ClipboardItem) -> some View {
        if let data = item.imageData, let img = NSImage(data: data) {
            // Same shape as the image-preview branch — a ScrollView absorbs the
            // scroll wheel; without it SwiftUI thrashed layout with the
            // resizable + aspect-fit + infinity-frame combo and the window froze.
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
            }
        } else if let path = item.filePath {
            VStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 128, maxHeight: 128)
                    .padding(24)
                Text(item.text)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private let previewHeaderFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

private func formatPreviewBytes(_ bytes: Int) -> String {
    let mb = Double(bytes) / (1024 * 1024)
    if mb >= 1 { return String(format: "%.2f MB", mb) }
    return String(format: "%.0f KB", Double(bytes) / 1024)
}
