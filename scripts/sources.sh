# Single source of truth for the swiftc file list.
#
# Both scripts/build_dmg.sh and .github/workflows/build.yml source this, so a
# new file only ever needs adding in one place. Keeping two copies meant a new
# file could build locally and break the release job.
#
# Secrets.swift is git-ignored — created by hand locally, generated from
# GitHub Secrets in CI.

TICKR_SOURCES=(
    Tickr/TickrApp.swift
    Tickr/Models/StockData.swift
    Tickr/Models/AppSettings.swift
    Tickr/Models/ClipboardItem.swift
    Tickr/Models/TodoItem.swift
    Tickr/Models/FilingItem.swift
    Tickr/Services/StockService.swift
    Tickr/Services/AnalyticsService.swift
    Tickr/Services/SuggestionsService.swift
    Tickr/Services/UpdateService.swift
    Tickr/Services/LicenseService.swift
    Tickr/Services/AdService.swift
    Tickr/Services/LaunchAtLoginService.swift
    Tickr/Services/NotificationService.swift
    Tickr/Services/ClipboardService.swift
    Tickr/Services/ClipboardSyncService.swift
    Tickr/Services/TodoService.swift
    Tickr/Services/TodoSyncService.swift
    Tickr/Services/SECService.swift
    Tickr/Services/HotKeyService.swift
    Tickr/Services/BackupService.swift
    Tickr/Services/Secrets.swift
    Tickr/Views/StatusBarController.swift
    Tickr/Views/TickerDropdownView.swift
    Tickr/Views/SettingsView.swift
    Tickr/Views/ClipboardHistoryWindow.swift
    Tickr/Views/TodoWindow.swift
    Tickr/Views/ShortcutRecorder.swift
    Tickr/Views/UpdateBanner.swift
)
