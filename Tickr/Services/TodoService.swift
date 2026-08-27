import Foundation
import AppKit

class TodoService: ObservableObject {
    static let shared = TodoService()

    @Published var items: [TodoItem] = []

    private static let persistKey = "todoItems"

    private init() {
        loadFromDisk()
    }

    // MARK: - Filters

    var active: [TodoItem]   { items.filter { !$0.done && !$0.archived } }
    var done:   [TodoItem]   { items.filter {  $0.done && !$0.archived } }
    var archived: [TodoItem] { items.filter {  $0.archived } }

    // MARK: - Mutations

    @discardableResult
    func add(_ text: String) -> TodoItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TodoItem(text: trimmed)
        var arr = items
        arr.insert(item, at: 0)
        items = arr
        saveToDisk()
        TodoSyncService.shared.pushIfEnabled(item: item)
        return item
    }

    func update(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var bumped = item
        bumped.updatedAt = Date()
        bumped.version = items[idx].version + 1
        items[idx] = bumped
        saveToDisk()
        TodoSyncService.shared.pushIfEnabled(item: bumped)
    }

    func toggleDone(_ item: TodoItem) {
        var copy = item
        copy.done.toggle()
        update(copy)
    }

    func toggleArchived(_ item: TodoItem) {
        var copy = item
        copy.archived.toggle()
        update(copy)
    }

    func edit(_ item: TodoItem, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = item
        copy.text = trimmed
        update(copy)
    }

    func remove(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        saveToDisk()
        TodoSyncService.shared.pushDeletionIfEnabled(itemId: item.id)
    }

    func clearArchived() {
        for item in archived {
            TodoSyncService.shared.pushDeletionIfEnabled(itemId: item.id)
        }
        items.removeAll { $0.archived }
        saveToDisk()
    }

    /// Merge a server-pushed item into local state. Newest version wins.
    func mergeRemote(_ item: TodoItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            if item.version >= items[idx].version {
                items[idx] = item
            }
        } else {
            var arr = items
            arr.insert(item, at: 0)
            items = arr
        }
        saveToDisk()
    }

    /// Hard-remove an item locally (used when sync says it was deleted elsewhere).
    func dropLocally(id: UUID) {
        items.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Replace the whole list (used by backup import).
    func replaceAll(_ newItems: [TodoItem]) {
        items = newItems
        saveToDisk()
    }

    // MARK: - Export

    /// Render the entire list as a portable Markdown document.
    func exportMarkdown() -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        var out = "# Todos\n\nExported \(df.string(from: Date()))\n\n"

        func section(_ title: String, _ list: [TodoItem]) -> String {
            guard !list.isEmpty else { return "" }
            var s = "## \(title)\n\n"
            for item in list {
                let box = item.done ? "x" : " "
                s += "- [\(box)] \(item.text)  _(\(df.string(from: item.createdAt)))_\n"
            }
            return s + "\n"
        }

        out += section("Active",   active)
        out += section("Done",     done)
        out += section("Archived", archived)
        return out
    }

    /// Show a Save panel and write the export to disk.
    func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "todos.md"
        panel.title = "Export Todos"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            let data = self.exportMarkdown().data(using: .utf8) ?? Data()
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        items = decoded
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.persistKey)
        }
    }
}
