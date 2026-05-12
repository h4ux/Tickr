import SwiftUI
import AppKit

class TodoWindowController {
    static let shared = TodoWindowController()
    private var fullWindow: NSWindow?
    private var quickWindow: NSWindow?

    private init() {}

    // MARK: - Full window (list, filters, search, export)

    func toggle() {
        if let w = fullWindow, w.isVisible {
            w.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        // Close the quick-entry window if it's up — only one Todo window at a time.
        quickWindow?.orderOut(nil)

        let preferredSize = NSSize(
            width: max(440, CGFloat(AppSettings.shared.todoWindowWidth)),
            height: max(360, CGFloat(AppSettings.shared.todoWindowHeight))
        )

        if let w = fullWindow {
            w.setContentSize(preferredSize)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: TodoView(onClose: { [weak self] in
            self?.fullWindow?.orderOut(nil)
        }))
        let w = NSPanel(contentViewController: host)
        w.setContentSize(preferredSize)
        w.minSize = NSSize(width: 440, height: 360)
        w.title = "Todos"
        w.styleMask = [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView]
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.level = .floating
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fullWindow = w
    }

    // MARK: - Quick-entry window (shortcut)

    func toggleQuickEntry() {
        if let w = quickWindow, w.isVisible {
            w.orderOut(nil)
        } else {
            showQuickEntry()
        }
    }

    func showQuickEntry() {
        fullWindow?.orderOut(nil)

        if let w = quickWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: TodoQuickEntryView(
            onShowAll: { [weak self] in
                self?.quickWindow?.orderOut(nil)
                self?.show()
            },
            onClose: { [weak self] in
                self?.quickWindow?.orderOut(nil)
            }
        ))
        let w = NSPanel(contentViewController: host)
        w.setContentSize(NSSize(width: 440, height: 110))
        w.title = "New Todo"
        w.styleMask = [.titled, .closable, .nonactivatingPanel, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.level = .floating
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        quickWindow = w
    }
}

private enum TodoFilter: String, CaseIterable, Identifiable {
    case active, done, archived, all

    var id: String { rawValue }
    var label: String {
        switch self {
        case .active:   return "Active"
        case .done:     return "Done"
        case .archived: return "Archived"
        case .all:      return "All"
        }
    }
}

struct TodoView: View {
    @ObservedObject private var todos = TodoService.shared
    @ObservedObject private var todoSync = TodoSyncService.shared
    @State private var entry = ""
    @State private var filter: TodoFilter = .active
    @State private var search = ""
    @State private var editingItem: TodoItem?
    @State private var editingText = ""
    @State private var keyMonitor: Any?
    let onClose: () -> Void

    private var visible: [TodoItem] {
        let base: [TodoItem]
        switch filter {
        case .active:   base = todos.active
        case .done:     base = todos.done
        case .archived: base = todos.archived
        case .all:      base = todos.items
        }
        guard !search.isEmpty else { return base }
        return base.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // New-entry bar (focused on open).
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
                TextField("New todo — press ⏎ to add", text: $entry)
                    .textFieldStyle(.plain)
                    .onSubmit { commitEntry() }
                if !entry.isEmpty {
                    Button(action: { entry = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Filter strip + search
            HStack(spacing: 8) {
                Picker("", selection: $filter) {
                    ForEach(TodoFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)

                Spacer()

                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 140)
            }
            .padding(8)

            Divider()

            // List
            if visible.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(visible) { item in
                            TodoRow(
                                item: item,
                                onToggleDone: { todos.toggleDone(item) },
                                onArchive: { todos.toggleArchived(item) },
                                onDelete: { todos.remove(item) },
                                onBeginEdit: {
                                    editingText = item.text
                                    editingItem = item
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            // Footer
            HStack(spacing: 8) {
                Text("\(todos.active.count) active  •  \(todos.done.count) done  •  \(todos.archived.count) archived")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if filter == .archived && !todos.archived.isEmpty {
                    Button("Clear archived") { todos.clearArchived() }
                        .font(.caption)
                }
                Button(action: { todos.exportToFile() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                if LicenseService.shared.isLicensed && AppSettings.shared.todoSyncEnabled {
                    Button(action: { todoSync.fetch() }) {
                        if todoSync.isFetching {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Pull synced todos")
                }
            }
            .padding(8)
        }
        .onAppear {
            installKeyMonitor()
            if LicenseService.shared.isLicensed && AppSettings.shared.todoSyncEnabled {
                todoSync.fetch()
            }
        }
        .onDisappear { removeKeyMonitor() }
        .sheet(item: $editingItem) { item in
            TodoEditSheet(
                text: $editingText,
                onSave: {
                    todos.edit(item, newText: editingText)
                    editingItem = nil
                },
                onCancel: { editingItem = nil }
            )
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .active:   return "Nothing to do. Add one above."
        case .done:     return "Nothing completed yet."
        case .archived: return "Nothing archived."
        case .all:      return "No todos yet."
        }
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc closes the window. The edit sheet is its own window and
            // handles Esc / ⌘. natively.
            if Int(event.keyCode) == 53 && editingItem == nil {
                onClose()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func commitEntry() {
        let added = todos.add(entry)
        if added != nil { entry = "" }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let onToggleDone: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onBeginEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleDone) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.done ? .accentColor : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .padding(.top, 1)

            Text(item.text)
                .strikethrough(item.done, color: .secondary)
                .foregroundColor(item.done ? .secondary : .primary)
                .lineLimit(4)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onBeginEdit() }

            if item.archived {
                Text("archived")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            Menu {
                Button(action: onBeginEdit) { Label("Edit", systemImage: "pencil") }
                Button(action: onArchive) {
                    Label(item.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

/// Multi-line edit sheet — opens as a sheet on the TodoView. Cmd+Return saves,
/// Esc cancels (handled by the textfield itself; the menu shortcut is for the Save button).
private struct TodoEditSheet: View {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit todo")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)

            Divider()

            TextEditor(text: $text)
                .font(.system(.body))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 520, minHeight: 360, idealHeight: 420)
    }
}

// MARK: - Quick entry

/// Compact window opened by the global shortcut. One focused text field —
/// ⏎ adds the todo and clears, Esc closes, "View All" switches to the full window.
struct TodoQuickEntryView: View {
    @ObservedObject private var todos = TodoService.shared
    @State private var text = ""
    @State private var justAdded: String?
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool
    let onShowAll: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                TextField("New todo — ⏎ to add", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(commit)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            HStack(spacing: 8) {
                if let last = justAdded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Added \"\(last)\"")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                } else {
                    Text("\(todos.active.count) active  •  \(todos.done.count) done")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onShowAll) {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet.rectangle")
                        Text("View All")
                    }
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(width: 440)
        .onAppear {
            focused = true
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = todos.add(trimmed)
        justAdded = trimmed
        text = ""
        focused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if justAdded == trimmed { justAdded = nil }
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == 53 {  // Esc
                onClose()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}
