import Foundation
import CryptoKit
import AppKit

/// Sync clipboard history to a Cloudflare KV namespace exposed via the worker.
/// Each entry is encrypted client-side with the user's sync key — the worker
/// only sees opaque blobs.
class ClipboardSyncService: ObservableObject {
    static let shared = ClipboardSyncService()

    @Published var lastUploadedAt: Date?
    @Published var lastError: String?
    @Published var isFetching = false

    private let settings = AppSettings.shared
    private let endpoints = [
        "https://service.h4ux.com/clipboard-sync",
        "https://tickr-service.alon-f46.workers.dev/clipboard-sync",
    ]

    private init() {}

    // MARK: - Key & sync-ID generation

    /// Generate a new random 32-byte sync key, base64url-encoded.
    /// The same key is used both as the AES-GCM symmetric key and (mixed with the
    /// user's email) to derive the KV slot identifier.
    static func generateSyncKey() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { raw in
            Data(raw).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
    }

    /// Sync-ID = hex(sha256("\(email):\(key)")). Used as the KV key so the
    /// email is never visible on the server.
    static func syncID(email: String, key: String) -> String {
        let input = "\(email.lowercased()):\(key)".data(using: .utf8) ?? Data()
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Encryption

    private func symmetricKey(from base64url: String) -> SymmetricKey? {
        var s = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-pad
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else { return nil }
        return SymmetricKey(data: data)
    }

    private func encrypt(_ plaintext: Data, with keyB64: String) -> Data? {
        guard let key = symmetricKey(from: keyB64) else { return nil }
        return try? AES.GCM.seal(plaintext, using: key).combined
    }

    private func decrypt(_ ciphertext: Data, with keyB64: String) -> Data? {
        guard let key = symmetricKey(from: keyB64) else { return nil }
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    // MARK: - Push / fetch

    /// Returns true if sync is configured AND the user is licensed.
    private var canSync: Bool {
        guard LicenseService.shared.isLicensed else { return false }
        guard settings.clipboardSyncEnabled else { return false }
        guard !settings.clipboardSyncKey.isEmpty else { return false }
        return true
    }

    /// Called by ClipboardService when a new item lands locally. No-op if sync is off.
    func pushIfEnabled(item: ClipboardItem) {
        guard canSync else { return }
        push(item: item)
    }

    /// Remove a single item from the server. No-op if sync is off.
    func pushDeletionIfEnabled(itemId: UUID) {
        guard canSync else { return }
        guard let url = URL(string: "\(endpoints[0])?sid=\(syncID)&iid=\(itemId.uuidString)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req).resume()
    }

    private func push(item: ClipboardItem) {
        guard let plaintext = try? JSONEncoder().encode(item) else { return }
        guard let cipher = encrypt(plaintext, with: settings.clipboardSyncKey) else {
            DispatchQueue.main.async { self.lastError = "Encryption failed" }
            return
        }
        upload(item: item, ciphertext: cipher, endpointIndex: 0)
    }

    private func upload(item: ClipboardItem, ciphertext: Data, endpointIndex: Int) {
        guard endpointIndex < endpoints.count,
              let url = URL(string: "\(endpoints[endpointIndex])?sid=\(syncID)&iid=\(item.id.uuidString)") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = ciphertext

        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastError = error.localizedDescription
                    return
                }
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    self?.lastUploadedAt = Date()
                    self?.lastError = nil
                } else {
                    // Try the next endpoint
                    self?.upload(item: item, ciphertext: ciphertext, endpointIndex: endpointIndex + 1)
                }
            }
        }.resume()
    }

    /// Pull all entries for this sync-ID from the worker and merge into local history.
    func fetch(completion: ((Bool) -> Void)? = nil) {
        guard canSync else { completion?(false); return }
        isFetching = true
        fetch(endpointIndex: 0, completion: completion)
    }

    private func fetch(endpointIndex: Int, completion: ((Bool) -> Void)?) {
        guard endpointIndex < endpoints.count,
              let url = URL(string: "\(endpoints[endpointIndex])?sid=\(syncID)") else {
            isFetching = false
            completion?(false)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.lastError = error.localizedDescription
                    self.fetch(endpointIndex: endpointIndex + 1, completion: completion)
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let entries = json["entries"] as? [[String: Any]] else {
                    self.fetch(endpointIndex: endpointIndex + 1, completion: completion)
                    return
                }

                var merged = ClipboardService.shared.items
                let existingIDs = Set(merged.map(\.id))

                for entry in entries {
                    guard let cipherB64 = entry["data"] as? String,
                          let cipher = Data(base64Encoded: cipherB64),
                          let plain = self.decrypt(cipher, with: self.settings.clipboardSyncKey),
                          let item = try? JSONDecoder().decode(ClipboardItem.self, from: plain),
                          !existingIDs.contains(item.id) else { continue }
                    merged.insert(item, at: 0)
                }
                merged.sort { $0.timestamp > $1.timestamp }
                let limit = max(1, self.settings.clipboardHistoryLimit)
                if merged.count > limit { merged = Array(merged.prefix(limit)) }
                ClipboardService.shared.items = merged
                self.isFetching = false
                self.lastError = nil
                completion?(true)
            }
        }.resume()
    }

    private var syncID: String {
        Self.syncID(email: LicenseService.shared.licensedEmail, key: settings.clipboardSyncKey)
    }
}
