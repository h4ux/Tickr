import Foundation
import AppKit

struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let assets: [GitHubAsset]
}

struct GitHubAsset: Decodable {
    let name: String
    let browser_download_url: String
    let size: Int
}

class UpdateService: ObservableObject {
    static let shared = UpdateService()

    // Change this to your GitHub repo after pushing
    static let repoOwner = "h4ux"
    static let repoName = "Tickr"
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private static let autoCheckKey = "autoCheckForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 86400 // 24 hours

    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: String?
    @Published var downloadSize: String?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var updateAvailable = false
    @Published var lastChecked: Date?
    @Published var errorMessage: String?

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil ? true : UserDefaults.standard.bool(forKey: Self.autoCheckKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey)
            objectWillChange.send()
        }
    }

    private init() {
        if let ts = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Double, ts > 0 {
            lastChecked = Date(timeIntervalSince1970: ts)
        }

        // Auto-check on launch if enabled and last check was > 24h ago
        if autoCheckEnabled {
            let lastCheck = UserDefaults.standard.double(forKey: Self.lastCheckKey)
            if Date().timeIntervalSince1970 - lastCheck > Self.checkInterval {
                checkForUpdates()
            }
        }
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        // Update check is configured

        isChecking = true
        errorMessage = nil

        let urlString = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            isChecking = false
            errorMessage = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tickr/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                self?.lastChecked = Date()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

                if let error = error {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                    self?.errorMessage = "Could not parse release info"
                    return
                }

                let remoteVersion = release.tag_name.replacingOccurrences(of: "v", with: "")
                self?.latestVersion = remoteVersion
                self?.releaseNotes = release.body

                // Find DMG asset
                if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                    self?.downloadURL = dmgAsset.browser_download_url
                    self?.downloadSize = Self.formatBytes(dmgAsset.size)
                }

                self?.updateAvailable = Self.isNewerVersion(remoteVersion, than: Self.currentVersion)
                self?.errorMessage = nil
            }
        }.resume()
    }

    func downloadAndInstall() {
        guard let urlString = downloadURL, let url = URL(string: urlString) else { return }
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        let downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                self?.isDownloading = false

                if let error = error {
                    self?.errorMessage = "Download failed: \(error.localizedDescription)"
                    return
                }

                guard let tempURL = tempURL else {
                    self?.errorMessage = "Download failed"
                    return
                }

                self?.installFromDMG(tempURL)
            }
        }

        // Observe progress
        let observation = downloadTask.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = progress.fractionCompleted
            }
        }
        // Keep observation alive
        objc_setAssociatedObject(downloadTask, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        downloadTask.resume()
    }

    private func installFromDMG(_ dmgURL: URL) {
        let fileManager = FileManager.default
        let downloadsDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destDMG = downloadsDir.appendingPathComponent("Tickr-update.dmg")

        // Copy DMG to Downloads
        try? fileManager.removeItem(at: destDMG)
        do {
            try fileManager.copyItem(at: dmgURL, to: destDMG)
        } catch {
            errorMessage = "Failed to save DMG: \(error.localizedDescription)"
            return
        }

        // Mount DMG, copy app, unmount, relaunch
        let script = """
        do shell script "
            # Mount DMG
            MOUNT_OUTPUT=$(hdiutil attach '\(destDMG.path)' -nobrowse 2>&1)
            MOUNT_POINT=$(echo \\"$MOUNT_OUTPUT\\" | grep '/Volumes/' | sed 's/.*\\(\\/Volumes\\/.*\\)/\\1/' | head -1 | xargs)

            if [ -z \\"$MOUNT_POINT\\" ]; then
                exit 1
            fi

            # Copy app to Applications
            rm -rf /Applications/Tickr.app
            cp -R \\"$MOUNT_POINT/Tickr.app\\" /Applications/Tickr.app

            # Unmount
            hdiutil detach \\"$MOUNT_POINT\\" 2>/dev/null

            # Clean up
            rm -f '\(destDMG.path)'

            # Relaunch
            sleep 1
            open /Applications/Tickr.app
        "
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if error != nil {
            // Fallback: just open the DMG for manual install
            errorMessage = "Auto-install failed. Opening DMG for manual install."
            NSWorkspace.shared.open(destDMG)
            return
        }

        // Quit current instance (new one will launch from the script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Helpers

    private static func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.0f KB", Double(bytes) / 1_000) }
        return "\(bytes) B"
    }
}
