import SwiftUI

@main
struct TerminalSettingsApp: App {
    @StateObject private var language = AppLanguageStore()

    var body: some Scene {
        WindowGroup(language.text(L("终端设置"))) {
            ContentView()
                .environmentObject(language)
                .frame(minWidth: 820, minHeight: 620)
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    language.refreshSystemLanguage()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1060, height: 760)
        .commands {
            WindowCommands(language: language)
        }

        Settings {
            VStack(spacing: 12) {
                AppMark(size: 52)
                Text(language.text(L("终端设置")))
                    .font(.headline)
                Text(language.text(L("隐藏 macOS 偏好的图形化控制面板")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(language.text(L("版本 ") +
                        (Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString"
                        ) as? String ?? "?")))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 360, height: 170)
            .environmentObject(language)
        }
    }
}

/// Keyboard access to the toolbar actions and categories. ⌘Z stays with
/// text editing, so undoing a system change uses ⌥⌘Z.
struct WindowCommands: Commands {
    @ObservedObject var language: AppLanguageStore
    @FocusedValue(\.windowCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .undoRedo) {
            Button(language.text(L("撤销上次更改"))) { actions?.undo() }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(actions?.canUndo != true)
        }
        CommandGroup(after: .sidebar) {
            Button(language.text(L("刷新状态"))) { actions?.refresh() }
                .keyboardShortcut("r")
                .disabled(actions?.canRefresh != true)
            Divider()
            ForEach(Array(SettingsCategory.allCases.enumerated()), id: \.element) { index, category in
                Button(language.text(category.title)) { actions?.select(category) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .disabled(actions == nil)
            }
        }
    }
}
