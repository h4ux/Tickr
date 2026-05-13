import AppKit
import SwiftUI

class UpdateBannerController {
    static let shared = UpdateBannerController()
    private var window: NSWindow?

    private init() {}

    func show(version: String, downloadSize: String?) {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingController(rootView: UpdateBannerView(
            version: version,
            downloadSize: downloadSize,
            onDownload: { [weak self] in
                UpdateService.shared.downloadAndInstall()
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        ))

        let w = NSPanel(contentViewController: host)
        w.styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
        w.backgroundColor = .clear
        w.isOpaque = false
        w.isMovableByWindowBackground = true
        w.hasShadow = true
        w.level = .statusBar
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let size = NSSize(width: 360, height: 130)
        w.setContentSize(size)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - size.width - 14,
                y: visible.maxY - size.height - 14
            )
            w.setFrameOrigin(origin)
        }
        w.orderFront(nil)
        window = w
    }

    func dismiss() {
        window?.orderOut(nil)
    }
}

struct UpdateBannerView: View {
    let version: String
    let downloadSize: String?
    let onDownload: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tickr update available")
                        .font(.system(.body, weight: .semibold))
                    HStack(spacing: 4) {
                        Text("Version \(version)")
                            .foregroundColor(.secondary)
                        if let size = downloadSize {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(size)
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }

            HStack {
                Spacer()
                Button("Later") { onDismiss() }
                    .buttonStyle(.bordered)
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.app")
                        Text("Download")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
