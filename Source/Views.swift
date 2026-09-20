import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var language: AppLanguageStore
    @StateObject private var store = PreferencesStore()
    @State private var selection: SettingsCategory? = .overview
    @State private var searchText = ""
    @State private var categoryPendingReset: SettingsCategory?

    private var selectedCategory: SettingsCategory {
        selection ?? .overview
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 280)
        } detail: {
            ZStack(alignment: .bottom) {
                detail
                NoticeHost(
                    notice: store.notice,
                    undo: store.undo,
                    dismiss: store.dismissNotice
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(language.text(L("终端设置")))
        .searchable(text: $searchText, placement: .toolbar, prompt: language.text(L("搜索设置功能")))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.undo()
                } label: {
                    Label(language.text(L("撤销上次更改")), systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo || store.isWorking)
                .help(language.text(store.undoSummary ?? L("没有可撤销的更改")))

                Button {
                    store.refreshAll()
                } label: {
                    if store.isRefreshing {
                        Label(language.text(L("正在读取")), systemImage: "hourglass")
                    } else {
                        Label(language.text(L("刷新状态")), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isWorking)
                .help(language.text(L("重新读取系统偏好")))

                if selectedCategory != .overview &&
                    selectedCategory != .advanced &&
                    searchText.isEmpty {
                    Button {
                        categoryPendingReset = selectedCategory
                    } label: {
                        Label(language.text(L("恢复本页设置")), systemImage: "arrow.counterclockwise")
                    }
                    .disabled(store.isWorking)
                    .help(language.text(L("按每项声明的恢复策略操作；隐藏扩展会删除当前用户显式值")))
                }
            }
        }
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(language.text(alert.title)),
                message: Text(language.text(alert.message)),
                dismissButton: .default(Text(language.text(L("好"))))
            )
        }
        .confirmationDialog(language.text(L("按逐项策略恢复“\(categoryPendingReset?.title ?? "")”设置？")),
            isPresented: Binding(
                get: { categoryPendingReset != nil },
                set: { if !$0 { categoryPendingReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(language.text(L("继续恢复")), role: .destructive) {
                if let category = categoryPendingReset {
                    store.resetCategory(category)
                }
                categoryPendingReset = nil
            }
            Button(language.text(L("取消")), role: .cancel) {
                categoryPendingReset = nil
            }
        } message: {
            Text(language.text(L("隐藏扩展会删除当前用户域中的显式值，即使它原本由其他工具或用户命令写入；系统设置增强或镜像只恢复本应用接管前保存的快照。未被本应用接管的增强或镜像项目不会改动。")))
        }
        .onAppear {
            store.refreshAll()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SettingsCategory.allCases) { category in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.text(category.title))
                        if category == .overview {
                            Text(language.text(store.macOSVersion))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: category.symbol)
                        .foregroundStyle(category == .overview ? .blue : .primary)
                }
                .tag(category)
                .padding(.vertical, 3)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: selectedCategory == .advanced ? "lock.trianglebadge.exclamationmark" : "lock.shield")
                    .foregroundStyle(selectedCategory == .advanced ? .orange : .green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.text(selectedCategory == .advanced ? L("高级操作") : L("仅当前用户")))
                        .font(.caption.weight(.medium))
                    Text(language.text(selectedCategory == .advanced ? L("每次更改均需系统授权") : L("无需管理员权限")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SearchResultsView(searchText: searchText, store: store)
        } else if selectedCategory == .overview {
            OverviewView(store: store, selection: $selection)
        } else {
            CategoryView(category: selectedCategory, store: store)
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var language: AppLanguageStore
    @ObservedObject var store: PreferencesStore
    @Binding var selection: SettingsCategory?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    AppMark(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text(L("终端设置")))
                            .font(.system(size: 28, weight: .bold))
                        Text(language.text(L("安全管理隐藏偏好与系统设置精确值")))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(language.text(store.isRefreshing ? "…" : "\(store.configuredCount)"))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text(language.text(L("项已显式配置")))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LanguageSettingsRow()

                InfoCard(
                    symbol: "checkmark.shield.fill",
                    tint: .green,
                    title: L("安全边界"),
                    detail: L("普通分类无需提权；由组织管理的偏好保持只读。高级分类仅执行固定白名单中的 pmset 布尔操作，并逐次请求管理员授权。应用不关闭 SIP、Gatekeeper 或文件隔离；所有写入都会校验、失败回滚并保留撤销记录。")
                )

                if let undoSummary = store.undoSummary {
                    UndoRecoveryCard(
                        summary: undoSummary,
                        isDisabled: store.isWorking,
                        action: store.undo
                    )
                }

                InfoCard(
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: L("区分写入成功与功能生效"),
                    detail: L("“实验性”表示未公开实现；同时标有“不稳定”时，表示值语义、当前可见效果或覆盖范围仍不确定。应用会校验偏好确实写入，但不会把读回成功冒充为功能已生效；每项不稳定设置都提供具体说明。")
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(language.text(L("浏览设置")))
                        .font(.title3.weight(.semibold))
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(SettingsCategory.allCases.filter { $0 != .overview }) { category in
                            Button {
                                selection = category
                            } label: {
                                CategoryTile(category: category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                    Text(language.text(L("所有开关都提供等价命令预览，实际执行不经过 shell，也不会解释输入中的特殊字符。")))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .frame(maxWidth: 920)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CategoryView: View {
    @EnvironmentObject private var language: AppLanguageStore
    let category: SettingsCategory
    @ObservedObject var store: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CategoryHeader(category: category, count: PreferenceCatalog.items(in: category).count)
                if category == .advanced {
                    InfoCard(
                        symbol: "lock.shield.fill",
                        tint: .orange,
                        title: L("管理员授权边界"),
                        detail: L("每个开关独立确认并向 macOS 请求管理员授权；系统可能复用近期认证。应用只把固定的 0/1 参数直接交给 /usr/bin/pmset，不启动 shell、不接受任意命令；不支持的硬件能力会保持不可操作。")
                    )
                } else if category == .trackpad {
                    InfoCard(
                        symbol: "testtube.2",
                        tint: .orange,
                        title: L("遗留手势实验"),
                        detail: L("这里只收录具有明确偏好地址、固定标量值和删除恢复路径，但在当前系统上语义或效果未确认的手势。写入可能无效、被系统覆盖或需要重新登录；请先阅读每项“不稳定说明”。")
                    )
                }
                VStack(spacing: 12) {
                    ForEach(PreferenceCatalog.items(in: category)) { item in
                        PreferenceRow(item: item, store: store)
                    }
                }
                Text(language.text(category == .advanced
                        ? L("高级开关关闭时明确写入 0；应用内撤销会恢复操作前各电源来源的真实值。")
                        : L("隐藏扩展会在确认后删除当前用户显式值（无论来源）；系统设置增强或镜像会保存并恢复本应用接管前值，不会用删除键冒充原设置。")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 920)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct LanguageSettingsRow: View {
    @EnvironmentObject private var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language.text(L("语言 / Language"))).font(.headline)
                Spacer()
                Picker("", selection: Binding(get: { language.choice }, set: language.select)) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { choice in
                        Text(verbatim: choice.nativeName).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                .accessibilityLabel(language.text(L("语言 / Language")))
                .accessibilityIdentifier("overview.language")
            }
            Text(language.text(L("立即切换应用界面；数字格式遵循系统区域。系统授权窗口、标准菜单及 Finder 名称可能需要重新启动或由 macOS 决定语言。")))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct SearchResultsView: View {
    @EnvironmentObject private var language: AppLanguageStore
    let searchText: String
    @ObservedObject var store: PreferencesStore

    private var results: [PreferenceItem] {
        PreferenceCatalog.search(searchText, resources: language.resources)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text(L("搜索结果")))
                            .font(.system(size: 26, weight: .bold))
                        Text(language.text(L("找到 \(results.count) 项与“\(searchText)”相关的设置功能")))
                            .foregroundStyle(.secondary)
                    }
                }

                if results.isEmpty {
                    ContentUnavailableView(language.text(L("没有匹配的设置")),
                        systemImage: "slider.horizontal.3",
                        description: Text(language.text(L("试试“截屏”“路径”“动画”或“程序坞”。")))
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    VStack(spacing: 12) {
                        ForEach(results) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(language.text(item.category.title), systemImage: item.category.symbol)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                PreferenceRow(item: item, store: store)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 920)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PreferenceRow: View {
    @EnvironmentObject private var language: AppLanguageStore
    let item: PreferenceItem
    @ObservedObject var store: PreferencesStore
    @State private var showsCommands = false
    @State private var showsCustomization = false
    @State private var asksToReset = false
    @State private var pendingPrivilegedValue: Bool?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var isBusy: Bool {
        store.busyItemIDs.contains(item.id)
    }

    private var state: PreferenceReadState {
        store.state(for: item)
    }

    private var compatibilityWarning: LocalizedText? {
        guard case .unverified(let message) = item.support() else { return nil }
        return message
    }

    private var managementState: PreferenceManagementState {
        store.managementState(for: item)
    }

    private var isFirstClassNumeric: Bool {
        if case .numeric = item.control { return true }
        return false
    }

    private var customizationDisclosureAnimation: Animation? {
        accessibilityReduceMotion
            ? nil
            : .smooth(duration: 0.22, extraBounce: 0)
    }

    private func toggleCustomizationDisclosure() {
        withAnimation(customizationDisclosureAnimation) {
            showsCustomization.toggle()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 5) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text(item.title))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                PreferenceClassificationBadge(
                                    label: item.source.exposure.label,
                                    color: sourceColor
                                )
                                if let enhancementKind = item.source.enhancementKind {
                                    PreferenceClassificationBadge(
                                        label: enhancementKind.label,
                                        color: sourceColor
                                    )
                                }
                                if let managementLabel = managementState.label {
                                    PreferenceClassificationBadge(
                                        label: managementLabel,
                                        color: .purple
                                    )
                                    .help(language.text(managementHelp))
                                }
                            }
                            if item.caution.label != nil || item.stability.label != nil ||
                                compatibilityWarning != nil {
                                HStack(spacing: 6) {
                                if let label = item.caution.label {
                                    PreferenceClassificationBadge(
                                        label: label,
                                        color: cautionColor
                                    )
                                }
                                if let label = item.stability.label {
                                    PreferenceClassificationBadge(
                                        label: label,
                                        color: .orange
                                    )
                                }
                                if let compatibilityWarning {
                                    PreferenceClassificationBadge(
                                        label: L("当前系统未验证"),
                                        color: .orange
                                    )
                                    .help(language.text(compatibilityWarning))
                                    .accessibilityLabel(language.text(L("当前系统未验证：\(compatibilityWarning)")))
                                }
                                }
                            }
                        }
                    }
                    Text(language.text(item.detail))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let restriction = store.contextRestrictions[item.id] {
                        Label(language.text(restriction), systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.purple)
                            .accessibilityIdentifier("preference.contextLock.\(item.id)")
                    }
                    HStack(spacing: 8) {
                        PreferenceStatusBadge(state: state)
                        Label(language.text(item.effectHint),
                            systemImage: item.requiresAdministrator
                                ? "lock.shield"
                                : "arrow.triangle.2.circlepath"
                        )
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }

                Spacer(minLength: 18)
                control
                    .disabled(!store.canModify(item))
            }

            Divider()

            HStack {
                if item.numericConfiguration != nil && !isFirstClassNumeric {
                    Button {
                        toggleCustomizationDisclosure()
                    } label: {
                        HStack(spacing: 5) {
                            Label(language.text(showsCustomization ? L("收起自定义") : L("自定义选项")),
                                systemImage: "slider.horizontal.3"
                            )
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .rotationEffect(.degrees(showsCustomization ? 90 : 0))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        store.isCustomizationEnabled(item) ? Color.accentColor : .secondary
                    )
                    .accessibilityLabel(language.text(PreferenceDisplayText.disclosureLabel(
                        title: item.title, action: showsCustomization ? L("收起自定义选项") : L("展开自定义选项")
                    )))
                    .accessibilityValue(language.text(showsCustomization ? L("已展开") : L("已折叠")))
                    .accessibilityIdentifier("customization.disclosure.\(item.id)")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsCommands.toggle()
                    }
                } label: {
                    Label(language.text(showsCommands ? L("隐藏详情") : L("详情与命令")), systemImage: "info.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(language.text(PreferenceDisplayText.disclosureLabel(
                    title: item.title, action: showsCommands ? L("收起详情与命令") : L("展开详情与命令")
                )))
                .accessibilityValue(language.text(showsCommands ? L("已展开") : L("已折叠")))
                .accessibilityIdentifier("commands.disclosure.\(item.id)")

                Spacer()
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                if item.supportsRecoveryAction {
                    Button {
                        asksToReset = true
                    } label: {
                        Label(language.text(item.recovery.actionTitle), systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!store.canRecover(item))
                    .help(language.text(recoveryHelp))
                    .accessibilityLabel(language.text(L("为\(item.title)执行\(item.recovery.actionTitle)")))
                }
            }

            if showsCustomization, item.numericConfiguration != nil {
                PreferenceCustomizationPanel(item: item, store: store)
                    .transition(.opacity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("customization.panel.\(item.id)")
            }

            if showsCommands {
                PreferenceDetails(item: item, store: store)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.6)
        )
        .confirmationDialog(language.text(L("为“\(item.title)”执行“\(item.recovery.actionTitle)”？")),
            isPresented: $asksToReset,
            titleVisibility: .visible
        ) {
            Button(language.text(item.recovery.actionTitle), role: .destructive) {
                store.reset(item)
            }
            Button(language.text(L("取消")), role: .cancel) {}
        } message: {
            Text(language.text(item.recovery.detail))
        }
        .confirmationDialog(language.text(L("“\(item.title)”需要管理员授权")),
            isPresented: Binding(
                get: { pendingPrivilegedValue != nil },
                set: { if !$0 { pendingPrivilegedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let enabled = pendingPrivilegedValue {
                Button(language.text(enabled ? L("继续开启") : L("继续关闭"))) {
                    pendingPrivilegedValue = nil
                    store.setToggle(item, enabled: enabled)
                }
            }
            Button(language.text(L("取消")), role: .cancel) {
                pendingPrivilegedValue = nil
            }
        } message: {
            Text(language.text(L("macOS 将请求管理员授权；如近期已经认证，系统可能直接复用。此操作只修改该功能在当前可用电源来源中的 0/1 状态，可通过应用内撤销恢复原值。")))
        }
    }

    private var cautionColor: Color {
        switch item.caution {
        case .interaction: return .orange
        case .privileged: return .purple
        case .compatibility: return .indigo
        case .none: return .secondary
        }
    }

    private var sourceColor: Color {
        switch item.source.exposure {
        case .terminalOnly: return .secondary
        case .systemSettingsEnhancement: return .teal
        case .systemSettingsMirror: return .blue
        }
    }

    private var managementHelp: LocalizedText {
        switch managementState {
        case .checking:
            return L("正在检查该偏好是否由配置描述文件强制管理。")
        case .forced(let addresses), .partiallyForced(let addresses):
            return L("以下地址由组织管理，整项保持只读：") +
                addresses.map(\.displayPath).joined(separator: "、")
        case .unknown(let message):
            return L("无法确认管理状态：\(message)")
        case .unmanaged, .notApplicable:
            return ""
        }
    }

    private var recoveryHelp: LocalizedText {
        if store.canRecover(item) { return item.recovery.detail }
        if case .restoreBaseline = item.recovery.strategy {
            return L("首次明确应用后才会保存接管前快照；当前没有可恢复记录。")
        }
        return item.recovery.detail
    }

    @ViewBuilder
    private var control: some View {
        switch item.control {
        case .toggle:
            Toggle(language.text(""), isOn: Binding(
                get: { store.isEnabled(item) },
                set: { store.setToggle(item, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(language.text(item.title))
            .accessibilityIdentifier("preference.toggle.\(item.id)")
        case .choice(let preference):
            Picker(language.text(""), selection: Binding(
                get: { store.selectedChoice(item) },
                set: { store.setChoice(item, optionID: $0) }
            )) {
                ForEach(preference.options) { option in
                    Text(language.text(option.title)).tag(option.id)
                }
                if store.selectedChoice(item) == "custom" {
                    Text(language.text(L("当前：\(store.customChoiceValues[item.id].map { LocalizedText(verbatim: $0) } ?? L("未知"))")))
                        .tag("custom")
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)
            .accessibilityLabel(language.text(item.title))
            .accessibilityIdentifier("preference.choice.\(item.id)")
        case .text(let preference):
            HStack(spacing: 8) {
                TextField(language.text(preference.placeholder),
                    text: Binding(
                        get: { store.textDrafts[item.id] ?? "" },
                        set: { store.textDrafts[item.id] = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 145)
                .onSubmit { store.applyText(item) }
                .accessibilityLabel(language.text(L("\(item.title)输入值")))
                .accessibilityIdentifier("preference.text.\(item.id)")
                Button(language.text(L("应用"))) {
                    store.applyText(item)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(language.text(L("应用\(item.title)")))
            }
        case .numeric:
            Button(language.text(showsCustomization ? L("收起精确值") : L("精确值选项"))) {
                toggleCustomizationDisclosure()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(language.text(showsCustomization ? L("收起\(item.title)的精确值选项") : L("展开\(item.title)的精确值选项")))
            .accessibilityIdentifier("preference.numeric.\(item.id)")
        case .privilegedToggle:
            Toggle(language.text(""), isOn: Binding(
                get: { store.isEnabled(item) },
                set: { pendingPrivilegedValue = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(language.text(L("\(item.title)，需要管理员权限")))
            .accessibilityIdentifier("preference.privilegedToggle.\(item.id)")
        }
    }
}

struct PreferenceClassificationBadge: View {
    @EnvironmentObject private var language: AppLanguageStore
    let label: LocalizedText
    let color: Color

    var body: some View {
        Text(language.text(label))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.11)))
            .accessibilityLabel(language.text(L("分类标记：\(label)")))
    }
}

struct PreferenceCustomizationPanel: View {
    @EnvironmentObject private var language: AppLanguageStore
    let item: PreferenceItem
    @ObservedObject var store: PreferencesStore

    private var isEnabled: Bool {
        store.isCustomizationEnabled(item)
    }

    private var parentToggleIsOff: Bool {
        if case .toggle = item.control {
            return !store.isEnabled(item)
        }
        return false
    }

    private var contextDescription: LocalizedText? {
        guard let address = item.contextAddresses.first(where: { $0.key == "magnification" })
        else { return nil }
        switch store.contextValues[address] {
        case .bool(false)?, .integer(0)?:
            return L("放大尺寸将在系统放大功能开启后生效；本组不会修改放大开关。")
        case .bool(true)?, .integer(1)?:
            return L("系统放大功能已开启；本组只修改普通尺寸与放大尺寸。")
        default:
            return L("系统放大状态未明确读取；本组只修改尺寸，放大开关保持原样。")
        }
    }

    var body: some View {
        if let customization = item.numericConfiguration {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(language.text(L("自定义选项")), systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                        Text(language.text(customization.detail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    Toggle(language.text(L("使用自定义值")), isOn: Binding(
                        get: { store.isCustomizationEnabled(item) },
                        set: { store.setCustomizationEnabled(item, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!store.canModify(item))
                    .accessibilityLabel(language.text(L("\(item.title)使用自定义值")))
                    .accessibilityIdentifier("customization.toggle.\(item.id)")
                }

                if isEnabled {
                    Divider()
                    if let contextDescription {
                        Label(language.text(contextDescription), systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("customization.context.\(item.id)")
                    }
                    HStack(alignment: .center, spacing: 10) {
                        Label(language.text(L("系统当前值来自最近一次刷新；载入操作只更新本应用草稿。")),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Spacer(minLength: 12)
                        Button(language.text(L("载入当前值到草稿"))) {
                            store.loadCurrentCustomizationValues(item)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!store.canLoadCurrentCustomizationValues(item))
                        .help(language.text(L("仅复制最近一次刷新读取的全部有效数值，不写入系统偏好")))
                        .accessibilityLabel(language.text(L("将\(item.title)系统当前值载入草稿")))
                        .accessibilityIdentifier("customization.loadCurrent.\(item.id)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(customization.parameters) { parameter in
                        NumericCustomizationControl(
                            item: item,
                            parameter: parameter,
                            store: store
                        )
                        .disabled(!store.canModify(item))
                    }

                    if let message = store.customizationValidationError(item) {
                        Label(language.text(message), systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("customization.validation.\(item.id)")
                    }

                    HStack(alignment: .center, spacing: 10) {
                        if parentToggleIsOff {
                            Label(language.text(L("功能当前关闭；数值已保存，将在主开关开启时应用。")),
                                systemImage: "clock.badge.checkmark"
                            )
                        } else {
                            Label(language.text(L("拖动只更新草稿，点击应用后才写入系统偏好。")),
                                systemImage: "checkmark.shield"
                            )
                        }
                        Spacer(minLength: 12)
                        Button(language.text(L("应用自定义值"))) {
                            store.applyCustomization(item)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!store.canApplyCustomization(item))
                        .accessibilityIdentifier("customization.apply.\(item.id)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        let presetName = item.source.exposure == .systemSettingsEnhancement
                            ? L("常用预设")
                            : L("安全预设")
                        Label(language.text(parentToggleIsOff
                                ? L("功能当前关闭；下次开启时使用\(presetName)：\(customization.presetSummary)")
                                : L("自定义编辑已关闭；当前系统值未更改。\(presetName)：\(customization.presetSummary)")),
                            systemImage: "checkmark.shield"
                        )
                        Spacer(minLength: 12)
                        if !customization.initializesDraftsFromCurrentValue {
                            Button(language.text(L("应用\(presetName)"))) {
                                store.applyCustomizationPreset(item)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!store.canApplyCustomizationPreset(item))
                            .accessibilityIdentifier("customization.applyPreset.\(item.id)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 0.7)
            )
        }
    }
}

struct NumericCustomizationControl: View {
    @EnvironmentObject private var language: AppLanguageStore
    let item: PreferenceItem
    let parameter: NumericPreferenceParameter
    @ObservedObject var store: PreferencesStore
    @State private var transientSliderValue: Double?
    @State private var isSliderEditing = false
    @State private var sliderLoadRevision: Int?
    @State private var exactText = ""
    @State private var exactInputError: LocalizedText?
    @State private var exactFocusLoadRevision: Int?
    @FocusState private var exactFieldIsFocused: Bool

    private var draftValue: Double {
        store.customizationDraft(for: item, parameter: parameter)
    }

    private var displayedValue: Double {
        transientSliderValue ?? draftValue
    }

    private var currentValue: NumericPreferenceCurrentValue {
        store.customizationCurrentValue(for: item, parameter: parameter)
    }

    private var currentValueDescription: LocalizedText {
        switch currentValue {
        case .loading:
            return L("读取中…")
        case .notSet:
            return L("未显式设置（采用当前有效默认）")
        case .value(let value, _):
            return parameter.displayValue(value)
        case .invalid(let rawValue):
            return L("不可载入（原始值 \(rawValue)）")
        case .unavailable(let message):
            return L("暂不可用（\(message)）")
        }
    }

    private var loadRevision: Int {
        store.customizationLoadRevision(for: item)
    }

    private var committedValue: Binding<Double> {
        Binding(
            get: { store.customizationDraft(for: item, parameter: parameter) },
            set: { store.setCustomizationDraft(item, parameter: parameter, value: $0) }
        )
    }

    private var transientValue: Binding<Double> {
        Binding(
            get: { transientSliderValue ?? draftValue },
            set: { newValue in
                if let sliderLoadRevision, sliderLoadRevision != loadRevision {
                    return
                }
                let normalizedValue = parameter.normalized(newValue)
                if isSliderEditing {
                    transientSliderValue = normalizedValue
                } else {
                    transientSliderValue = nil
                    store.setCustomizationDraft(
                        item,
                        parameter: parameter,
                        value: normalizedValue
                    )
                }
            }
        )
    }

    private var stepperValue: Binding<Double> {
        Binding(
            get: { displayedValue },
            set: { newValue in
                isSliderEditing = false
                sliderLoadRevision = nil
                transientSliderValue = nil
                store.setCustomizationDraft(
                    item,
                    parameter: parameter,
                    value: newValue
                )
            }
        )
    }

    private func commitTransientSliderValue() {
        guard let transientSliderValue else { return }
        store.setCustomizationDraft(
            item,
            parameter: parameter,
            value: transientSliderValue
        )
        self.transientSliderValue = nil
    }

    private func sliderEditingChanged(_ isEditing: Bool) {
        isSliderEditing = isEditing
        if isEditing {
            sliderLoadRevision = loadRevision
            if transientSliderValue == nil {
                transientSliderValue = draftValue
            }
        } else {
            if sliderLoadRevision == loadRevision {
                commitTransientSliderValue()
            } else {
                transientSliderValue = nil
            }
            sliderLoadRevision = nil
        }
    }

    private func adjustByOneStep(_ direction: AccessibilityAdjustmentDirection) {
        let delta: Double
        switch direction {
        case .increment:
            delta = parameter.step
        case .decrement:
            delta = -parameter.step
        @unknown default:
            return
        }
        let baseValue = displayedValue
        isSliderEditing = false
        sliderLoadRevision = nil
        transientSliderValue = nil
        store.setCustomizationDraft(
            item,
            parameter: parameter,
            value: min(max(baseValue + delta, parameter.range.lowerBound), parameter.range.upperBound)
        )
    }

    private func formattedInput(_ value: Double) -> String {
        if parameter.precision == 0 {
            return String(Int(parameter.normalized(value).rounded()))
        }
        return String(
            format: "%.*f",
            locale: Locale.current,
            parameter.precision,
            parameter.normalized(value)
        )
    }

    private func parseExactInput() -> Double? {
        RegionalNumberInput.parse(exactText)
    }

    @discardableResult
    private func updateDraftFromExactInput(formatAfterCommit: Bool) -> Bool {
        guard let value = parseExactInput() else {
            exactInputError = L("请输入有效数值")
            store.setCustomizationInputError(
                item,
                parameter: parameter,
                message: exactInputError
            )
            return false
        }
        if let message = parameter.exactInputError(for: value) {
            exactInputError = message
            store.setCustomizationInputError(item, parameter: parameter, message: message)
            return false
        }
        isSliderEditing = false
        sliderLoadRevision = nil
        transientSliderValue = nil
        exactInputError = nil
        store.setCustomizationInputError(item, parameter: parameter, message: nil)
        store.setCustomizationDraft(item, parameter: parameter, value: value)
        if formatAfterCommit {
            exactText = formattedInput(value)
        }
        return true
    }

    private func commitExactInput() {
        _ = updateDraftFromExactInput(formatAfterCommit: true)
    }

    @ViewBuilder
    private var slider: some View {
        if parameter.usesContinuousSliderTrack {
            // The Binding keeps the exact 0.001 model resolution without asking
            // SwiftUI 26 to enumerate thousands of stepped ticks. Draft changes
            // stay local during dragging and are persisted once editing ends.
            Slider(
                value: transientValue,
                in: parameter.range,
                onEditingChanged: sliderEditingChanged
            )
            .accessibilityAdjustableAction(adjustByOneStep)
        } else if #available(macOS 26.0, *) {
            Slider(
                value: committedValue,
                in: parameter.range,
                step: parameter.step,
                neutralValue: nil,
                enabledBounds: parameter.range,
                label: { EmptyView() },
                tick: { _ in nil }
            )
        } else {
            Slider(value: committedValue, in: parameter.range, step: parameter.step)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(parameter.title))
                        .font(.subheadline.weight(.medium))
                    Text(language.text(parameter.detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(language.text(L("待应用草稿")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(language.text(parameter.displayValue(displayedValue)))
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(language.text(L("\(parameter.title)待应用草稿")))
                .accessibilityValue(language.text(parameter.displayValue(displayedValue)))
                .accessibilityIdentifier(
                    "customization.draft.\(item.id).\(parameter.id)"
                )
            }

            Label(language.text(L("系统当前精确值：\(currentValueDescription)")),
                systemImage: "desktopcomputer"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(language.text(L("\(parameter.title)系统当前精确值")))
            .accessibilityValue(language.text(currentValueDescription))
            .accessibilityIdentifier(
                "customization.current.\(item.id).\(parameter.id)"
            )

            if !parameter.specialValues.isEmpty {
                Picker(language.text(L("计时方式")), selection: Binding<Double?>(
                    get: { parameter.specialValue(for: draftValue)?.value },
                    set: { store.setCustomizationSpecialValue(item, parameter: parameter, value: $0) }
                )) {
                    Text(language.text(L("指定闲置时间"))).tag(Optional<Double>.none)
                    ForEach(parameter.specialValues) { special in
                        Text(language.text(special.title)).tag(Optional(special.value))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("customization.special.\(item.id).\(parameter.id)")
            }

            if !parameter.presets.isEmpty {
                HStack(spacing: 6) {
                    Text(language.text(L("草稿预设"))).font(.caption).foregroundStyle(.secondary)
                    ForEach(parameter.presets) { preset in
                        Button(language.text(preset.title)) {
                            store.applyCustomizationDraftPreset(
                                item, parameter: parameter, value: preset.value
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier(
                            "customization.preset.\(item.id).\(parameter.id).\(Int(preset.value))"
                        )
                    }
                }
            }

            if parameter.specialValue(for: displayedValue) == nil {
              HStack(spacing: 10) {
                slider
                    .accessibilityLabel(language.text(parameter.title))
                    .accessibilityValue(language.text(parameter.displayValue(displayedValue)))
                    .accessibilityIdentifier(
                        "customization.slider.\(item.id).\(parameter.id)"
                    )
                Stepper(language.text(""), value: stepperValue, in: parameter.range, step: parameter.step)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel(language.text(L("微调\(parameter.title)")))
                TextField(language.text(L("精确值")), text: $exactText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: parameter.precision == 0 ? 72 : 88)
                    .focused($exactFieldIsFocused)
                    .onSubmit(commitExactInput)
                    .accessibilityLabel(language.text(L("\(parameter.title)精确值")))
                    .accessibilityIdentifier(
                        "customization.exact.\(item.id).\(parameter.id)"
                    )
              }
            } else {
                Text(language.text(L("永不自动启动屏幕保护程序；点击应用后才更改系统计时。")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let exactInputError {
                Label(language.text(exactInputError), systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack {
                Text(language.text(parameter.displayValue(parameter.range.lowerBound)))
                Spacer()
                Label(language.text(L("允许范围 \(parameter.rangeLabel)")), systemImage: "shield.checkered")
                Spacer()
                Text(language.text(parameter.displayValue(parameter.range.upperBound)))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .onAppear {
            exactText = formattedInput(displayedValue)
            store.setCustomizationInputError(item, parameter: parameter, message: nil)
        }
        .onChange(of: exactText) { _, _ in
            if exactFieldIsFocused {
                _ = updateDraftFromExactInput(formatAfterCommit: false)
            }
        }
        .onChange(of: displayedValue) { _, newValue in
            if !exactFieldIsFocused {
                exactText = formattedInput(newValue)
                exactInputError = nil
                store.setCustomizationInputError(item, parameter: parameter, message: nil)
            }
        }
        .onChange(of: loadRevision) { _, _ in
            transientSliderValue = nil
            exactInputError = nil
            exactText = formattedInput(draftValue)
            store.setCustomizationInputError(item, parameter: parameter, message: nil)
        }
        .onChange(of: exactFieldIsFocused) { _, isFocused in
            if isFocused {
                exactFocusLoadRevision = loadRevision
            } else {
                if exactFocusLoadRevision == loadRevision, !exactText.isEmpty {
                    commitExactInput()
                } else if exactFocusLoadRevision != loadRevision {
                    exactInputError = nil
                    exactText = formattedInput(draftValue)
                    store.setCustomizationInputError(
                        item,
                        parameter: parameter,
                        message: nil
                    )
                }
                exactFocusLoadRevision = nil
            }
        }
        .onDisappear {
            isSliderEditing = false
            if sliderLoadRevision == nil || sliderLoadRevision == loadRevision {
                commitTransientSliderValue()
            } else {
                transientSliderValue = nil
            }
            sliderLoadRevision = nil
            store.setCustomizationInputError(item, parameter: parameter, message: nil)
        }
    }
}

private struct NoticeHost: View {
    @EnvironmentObject private var language: AppLanguageStore
    let notice: AppNotice?
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if let notice {
                NoticeView(notice: notice, undo: undo, dismiss: dismiss)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: notice?.id)
    }
}

struct PreferenceStatusBadge: View {
    @EnvironmentObject private var language: AppLanguageStore
    let state: PreferenceReadState

    private var color: Color {
        switch state {
        case .enabled, .configured: return .blue
        case .systemDefault, .disabled: return .secondary
        case .loading: return .secondary
        case .unverified: return .orange
        case .unsupported, .error: return .red
        }
    }

    private var symbol: String {
        switch state {
        case .enabled, .configured: return "checkmark.circle.fill"
        case .systemDefault: return "circle.dotted"
        case .disabled: return "circle"
        case .loading: return "hourglass"
        case .unverified: return "questionmark.circle"
        case .unsupported: return "nosign"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        Label(language.text(state.label), systemImage: symbol)
            .help(language.text(state.label))
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.1)))
            .accessibilityLabel(language.text(L("当前状态：\(state.label)")))
    }
}

struct PreferenceDetails: View {
    @EnvironmentObject private var language: AppLanguageStore
    let item: PreferenceItem
    @ObservedObject var store: PreferencesStore
    @State private var asksToDiscardRecoveryBaseline = false

    private var riskColor: Color {
        switch item.caution.risk {
        case .low: return .green
        case .medium: return .orange
        case .experimental: return .indigo
        case .privileged: return .purple
        }
    }

    private var compatibilityWarning: LocalizedText? {
        guard case .unverified(let message) = item.support() else { return nil }
        return message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Label(language.text(item.caution.risk.label), systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(riskColor)
                Label(language.text(item.source.detailLabel), systemImage: "signpost.right")
                    .foregroundStyle(.secondary)
                Label(language.text(item.compatibility.summary), systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if let compatibilityWarning {
                Label(language.text(compatibilityWarning), systemImage: "questionmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
            }

            if let instabilityNote = item.stability.note {
                VStack(alignment: .leading, spacing: 6) {
                    Label(language.text(L("不稳定说明")), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(language.text(instabilityNote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(language.text(L("可能结果：按说明生效、只部分生效、完全无效或在系统更新后改变。恢复行为以本项下方列出的策略为准。")))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "books.vertical")
                    .foregroundStyle(.secondary)
                Text(language.text(L("依据：")))
                    .foregroundStyle(.secondary)
                if let urlString = item.evidence.url, let url = URL(string: urlString) {
                    Link(language.text(item.evidence.title), destination: url)
                } else {
                    Text(language.text(item.evidence.title))
                }
            }
            .font(.caption)

            if let systemSettings = item.source.systemSettings {
                VStack(alignment: .leading, spacing: 4) {
                    Label(language.text(L("系统设置关系：\(systemSettings.coverage.label)")), systemImage: "gear")
                        .font(.caption.weight(.semibold))
                    Text(language.text(systemSettings.path))
                        .font(.caption)
                    Text(language.text(L("核对于 \(systemSettings.verifiedOSVersion)：\(systemSettings.note)")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let note = item.source.note {
                        Text(language.text(note))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(language.text(L("恢复策略：\(item.recovery.actionTitle)")), systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                Text(language.text(item.recovery.detail))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if store.canDiscardRecoveryBaseline(item) {
                    Button(language.text(L("放弃旧接管记录…"))) {
                        asksToDiscardRecoveryBaseline = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(language.text(L("只清除本应用保存的旧快照，不写入系统偏好；下次应用时会以系统当前值建立新基线。")))
                }
            }

            if let managementLabel = store.managementState(for: item).label {
                Label(language.text(managementLabel), systemImage: "building.2.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(language.text(item.requiresAdministrator ? L("受控管理员能力") : L("偏好地址")))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let key = item.privilegedKey {
                    Text(language.text(L("/usr/bin/pmset · \(key) · 布尔值 0/1")))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    ForEach(item.allAddresses, id: \.self) { address in
                        Text(language.text(address.displayPath))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }

            CommandPreview(commands: store.previewCommands(for: item), store: store)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.42))
        )
        .confirmationDialog(language.text(L("放弃“\(item.title)”的旧接管记录？")),
            isPresented: $asksToDiscardRecoveryBaseline,
            titleVisibility: .visible
        ) {
            Button(language.text(L("放弃记录")), role: .destructive) {
                store.discardRecoveryBaseline(item)
            }
            Button(language.text(L("取消")), role: .cancel) {}
        } message: {
            Text(language.text(L("此操作不会写入系统偏好，但之后无法再恢复到旧快照。下次明确应用时，会把系统当前值保存为新的接管前基线。")))
        }
    }
}

struct CommandPreview: View {
    @EnvironmentObject private var language: AppLanguageStore
    let commands: [(LocalizedText, String)]
    @ObservedObject var store: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(commands.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text(entry.0))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 8) {
                        Text(language.text(entry.1))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            store.copyCommand(entry.1)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help(language.text(L("复制命令")))
                        .accessibilityLabel(language.text(L("复制\(entry.0)命令")))
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                    )
                }
            }
        }
        .padding(.top, 2)
    }
}

struct CategoryHeader: View {
    @EnvironmentObject private var language: AppLanguageStore
    let category: SettingsCategory
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.gradient)
                Image(systemName: category.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(category.title))
                    .font(.system(size: 26, weight: .bold))
                Text(language.text(L("\(category.subtitle) · \(count) 项")))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct CategoryTile: View {
    @EnvironmentObject private var language: AppLanguageStore
    let category: SettingsCategory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: category.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 43, height: 43)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(category.title))
                    .font(.headline)
                Text(language.text(L("\(PreferenceCatalog.items(in: category).count) 项 · \(category.subtitle)")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.6)
        )
        .contentShape(Rectangle())
    }
}

struct InfoCard: View {
    @EnvironmentObject private var language: AppLanguageStore
    let symbol: String
    let tint: Color
    let title: LocalizedText
    let detail: LocalizedText

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text(title))
                    .font(.headline)
                Text(language.text(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 0.7)
        )
    }
}

struct UndoRecoveryCard: View {
    @EnvironmentObject private var language: AppLanguageStore
    let summary: LocalizedText
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(L("保留了上次撤销点")))
                    .font(.headline)
                Text(language.text(summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(language.text(L("撤销")), action: action)
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.16), lineWidth: 0.7)
        )
    }
}

struct NoticeView: View {
    @EnvironmentObject private var language: AppLanguageStore
    let notice: AppNotice
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(language.text(notice.message))
                .font(.subheadline.weight(.medium))
            if notice.canUndo {
                Button(language.text(L("撤销")), action: undo)
                    .buttonStyle(.borderless)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .accessibilityLabel(language.text(L("关闭提示")))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }
}

struct AppMark: View {
    @EnvironmentObject private var language: AppLanguageStore
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.53, blue: 0.98), Color(red: 0.18, green: 0.35, blue: 0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "terminal.fill")
                .font(.system(size: size * 0.44, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .blue.opacity(0.2), radius: 10, y: 4)
    }
}
