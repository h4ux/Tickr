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
        let tmpDir = fileManager.temporaryDirectory
        let destDMG = tmpDir.appendingPathComponent("Tickr-update.dmg")
        let updaterScript = tmpDir.appendingPathComponent("tickr_updater.sh")

        // Copy DMG to temp
        try? fileManager.removeItem(at: destDMG)
        do {
            try fileManager.copyItem(at: dmgURL, to: destDMG)
        } catch {
            errorMessage = "Failed to save DMG: \(error.localizedDescription)"
            return
        }

        // Get the current app's path and PID
        let appPath = Bundle.main.bundlePath
        let appInstallPath = appPath.isEmpty ? "/Applications/Tickr.app" : appPath
        let pid = ProcessInfo.processInfo.processIdentifier

        let logPath = tmpDir.appendingPathComponent("tickr_updater.log").path

        // Write the updater script — self-daemonizing via nohup re-exec
        let script = """
        #!/bin/bash
        # Tickr Updater

        LOG="\(logPath)"

        # Re-exec detached from parent if not already
        if [ "$TICKR_DETACHED" != "1" ]; then
            export TICKR_DETACHED=1
            nohup "$0" "$@" > "$LOG" 2>&1 &
            disown
            exit 0
        fi

        echo "=== Tickr updater started at $(date) ==="

        DMG_PATH="\(destDMG.path)"
        APP_INSTALL_PATH="\(appInstallPath)"
        APP_PID=\(pid)

        echo "DMG: $DMG_PATH"
        echo "App: $APP_INSTALL_PATH"
        echo "PID: $APP_PID"

        # Wait for the app to quit
        for i in $(seq 1 20); do
            if ! kill -0 "$APP_PID" 2>/dev/null; then
                echo "App quit after ${i} checks"
                break
            fi
            sleep 0.5
        done
        kill -9 "$APP_PID" 2>/dev/null
        sleep 1

        # Mount DMG
        echo "Mounting DMG..."
        MOUNT_OUTPUT=$(hdiutil attach "$DMG_PATH" -nobrowse -noverify 2>&1)
        echo "$MOUNT_OUTPUT"
        MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | sed 's/.*\\(\\/Volumes\\/.*\\)/\\1/' | head -1 | xargs)

        if [ -z "$MOUNT_POINT" ]; then
            echo "ERROR: Failed to mount DMG"
            open "$DMG_PATH"
            exit 1
        fi

        echo "Mounted at: $MOUNT_POINT"

        NEW_APP=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
        if [ -z "$NEW_APP" ]; then
            echo "ERROR: No .app found in DMG"
            hdiutil detach "$MOUNT_POINT" 2>/dev/null
            open "$DMG_PATH"
            exit 1
        fi

        echo "New app: $NEW_APP"

        # Replace old app
        echo "Removing old app..."
        rm -rf "$APP_INSTALL_PATH"
        echo "Copying new app..."
        cp -R "$NEW_APP" "$APP_INSTALL_PATH"
        COPY_RESULT=$?

        # Unmount
        hdiutil detach "$MOUNT_POINT" 2>/dev/null
        rm -f "$DMG_PATH"

        if [ $COPY_RESULT -ne 0 ]; then
            echo "ERROR: Copy failed"
            exit 1
        fi

        echo "Relaunching..."
        open "$APP_INSTALL_PATH"
        echo "=== Update complete ==="
        """

        do {
            try script.write(to: updaterScript, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: updaterScript.path)
        } catch {
            errorMessage = "Failed to create updater: \(error.localizedDescription)"
            return
        }

        // Launch via /usr/bin/open with a shell wrapper to ensure detachment
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [updaterScript.path]
        process.standardOutput = FileHandle(forWritingAtPath: logPath) ?? FileHandle.nullDevice
        process.standardError = FileHandle(forWritingAtPath: logPath) ?? FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            errorMessage = "Failed to launch updater: \(error.localizedDescription)"
            NSWorkspace.shared.open(destDMG)
            return
        }

        // Quit the app — updater takes over. Longer delay to let script detach.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
