import Foundation
import CommonCrypto

class LicenseService: ObservableObject {
    static let shared = LicenseService()

    // Loaded from Secrets.swift (git-ignored) — MUST match scripts/.license_secret
    private static let secret = Secrets.licenseSecret
    private static let emailKey = "licenseEmail"
    private static let keyKey = "licenseKey"

    @Published var isLicensed: Bool = false
    @Published var licensedEmail: String = ""

    private init() {
        let email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        let key = UserDefaults.standard.string(forKey: Self.keyKey) ?? ""
        if !email.isEmpty && !key.isEmpty && Self.verify(email: email, key: key) {
            isLicensed = true
            licensedEmail = email
        }
    }

    func activate(email: String, key: String) -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard Self.verify(email: cleanEmail, key: cleanKey) else { return false }

        UserDefaults.standard.set(cleanEmail, forKey: Self.emailKey)
        UserDefaults.standard.set(cleanKey, forKey: Self.keyKey)
        isLicensed = true
        licensedEmail = cleanEmail

        // Track activation
        AnalyticsService.shared.track("license_activated", properties: ["email_domain": String(cleanEmail.split(separator: "@").last ?? "")])

        return true
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        UserDefaults.standard.removeObject(forKey: Self.keyKey)
        isLicensed = false
        licensedEmail = ""
        AnalyticsService.shared.track("license_deactivated")
    }

    // MARK: - HMAC-SHA256 verification (matches Python generator)

    private static func verify(email: String, key: String) -> Bool {
        let expected = generateKey(for: email)
        return expected == key
    }

    private static func generateKey(for email: String) -> String {
        let email = email.lowercased()
        let key = secret.data(using: .utf8)!
        let data = email.data(using: .utf8)!

        var hmacBytes = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { dataPtr in
            key.withUnsafeBytes { keyPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyPtr.baseAddress!, key.count,
                        dataPtr.baseAddress!, data.count,
                        &hmacBytes)
            }
        }

        let hex = hmacBytes.map { String(format: "%02x", $0) }.joined()
        let prefix = String(hex.prefix(25)).uppercased()

        // Format as 5 groups of 5
        var parts: [String] = []
        var idx = prefix.startIndex
        for _ in 0..<5 {
            let end = prefix.index(idx, offsetBy: 5)
            parts.append(String(prefix[idx..<end]))
            idx = end
        }
        return parts.joined(separator: "-")
    }
}
