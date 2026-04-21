import Foundation
import ServiceManagement
import AppKit

class LaunchAtLoginService: ObservableObject {
    static let shared = LaunchAtLoginService()

    @Published var isEnabled: Bool = false
    @Published var status: SMAppService.Status = .notRegistered
    @Published var errorMessage: String?

    private init() {
        refresh()
    }

    func refresh() {
        let current = SMAppService.mainApp.status
        status = current
        isEnabled = (current == .enabled)
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    refresh()
                    return
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            errorMessage = error.localizedDescription
            refresh()
        }
    }

    func openLoginItemsSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.general",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    var statusDescription: String {
        switch status {
        case .notRegistered:    return "Not enabled"
        case .enabled:          return "Enabled"
        case .requiresApproval: return "Waiting for approval in System Settings"
        case .notFound:         return "App not found in Login Items"
        @unknown default:       return "Unknown"
        }
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }
}
