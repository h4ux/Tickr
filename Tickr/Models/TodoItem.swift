import Foundation

struct TodoItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var done: Bool
    var archived: Bool
    let createdAt: Date
    var updatedAt: Date
    /// Track edits separately so synced clients can resolve "newer wins".
    var version: Int

    init(id: UUID = UUID(),
         text: String,
         done: Bool = false,
         archived: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         version: Int = 1) {
        self.id = id
        self.text = text
        self.done = done
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
}
