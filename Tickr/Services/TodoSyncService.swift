import Foundation
import CryptoKit
import AppKit

class TodoSyncService: ObservableObject {
    static let shared = TodoSyncService()

    @Published var isFetching = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?

    private let settings = AppSettings.shared
    private let endpoints = [
        "https://service.h4ux.com/notes-sync",
        "https://tickr-service.alon-f46.workers.dev/notes-sync",
    ]

    private init() {}

    // MARK: - Sync ID + key

    /// Note sync slot is namespaced separately from clipboard sync so the
    /// two never collide in KV. Uses the same user-supplied key for crypto.
    static func syncID(email: String, key: String) -> String {
        let input = "notes:\(email.lowercased()):\(key)".data(using: .utf8) ?? Data()
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private var syncID: String {
        Self.syncID(email: LicenseService.shared.licensedEmail, key: settings.clipboardSyncKey)
    }

    private var canSync: Bool {
        guard LicenseService.shared.isLicensed else { return false }
        guard settings.todoSyncEnabled else { return false }
        guard !settings.clipboardSyncKey.isEmpty else { return false }
        return true
    }

    private func symmetricKey(from base64url: String) -> SymmetricKey? {
        var s = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else { return nil }
        return SymmetricKey(data: data)
    }

    private func encrypt(_ plaintext: Data) -> Data? {
        guard let key = symmetricKey(from: settings.clipboardSyncKey) else { return nil }
        return try? AES.GCM.seal(plaintext, using: key).combined
    }

    private func decrypt(_ ciphertext: Data) -> Data? {
        guard let key = symmetricKey(from: settings.clipboardSyncKey) else { return nil }
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    // MARK: - Push / pull

    func pushIfEnabled(item: TodoItem) {
        guard canSync else { return }
        push(item: item)
    }

    private func push(item: TodoItem) {
        guard let plaintext = try? JSONEncoder().encode(item),
              let cipher = encrypt(plaintext) else { return }
        upload(itemID: item.id, ciphertext: cipher, endpointIndex: 0)
    }

    private func upload(itemID: UUID, ciphertext: Data, endpointIndex: Int) {
        guard endpointIndex < endpoints.count,
              let url = URL(string: "\(endpoints[endpointIndex])?sid=\(syncID)&iid=\(itemID.uuidString)") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = ciphertext

        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if error != nil || (response as? HTTPURLResponse)?.statusCode ?? 0 >= 400 {
                    self?.upload(itemID: itemID, ciphertext: ciphertext, endpointIndex: endpointIndex + 1)
                    return
                }
                self?.lastSyncedAt = Date()
                self?.lastError = nil
            }
        }.resume()
    }

    func pushDeletionIfEnabled(itemId: UUID) {
        guard canSync else { return }
        guard let url = URL(string: "\(endpoints[0])?sid=\(syncID)&iid=\(itemId.uuidString)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req).resume()
    }

    func fetch(completion: ((Bool) -> Void)? = nil) {
        guard canSync else { completion?(false); return }
        isFetching = true
        fetch(endpointIndex: 0, completion: completion)
    }

    private func fetch(endpointIndex: Int, completion: ((Bool) -> Void)?) {
        guard endpointIndex < endpoints.count,
              let url = URL(string: "\(endpoints[endpointIndex])?sid=\(syncID)") else {
            DispatchQueue.main.async {
                self.isFetching = false
                completion?(false)
            }
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let data = data,
                      let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let entries = json["entries"] as? [[String: Any]] else {
                    self.fetch(endpointIndex: endpointIndex + 1, completion: completion)
                    return
                }

                for entry in entries {
                    guard let b64 = entry["data"] as? String,
                          let cipher = Data(base64Encoded: b64),
                          let plain = self.decrypt(cipher),
                          let item = try? JSONDecoder().decode(TodoItem.self, from: plain) else { continue }
                    TodoService.shared.mergeRemote(item)
                }

                self.isFetching = false
                self.lastSyncedAt = Date()
                self.lastError = nil
                completion?(true)
            }
        }.resume()
    }
}
