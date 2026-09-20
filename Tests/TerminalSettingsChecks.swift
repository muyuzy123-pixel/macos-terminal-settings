import Darwin
import Foundation

enum CheckFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

private enum RecordingDependencyEvent: CustomStringConvertible {
    case preferenceSnapshots([PreferenceAddress])
    case preferenceVerify([PreferenceSnapshot])
    case preferenceEnsureUnchanged([PreferenceSnapshot])
    case preferenceEnsureCurrentMatchesAny
    case preferenceRead([PreferenceAddress])
    case preferenceApply(PreferenceAddress, PreferenceValue?)
    case preferenceRestore([PreferenceSnapshot])
    case preferenceRestorePreservingExternalChanges
    case restart([String])
    case managementRead([PreferenceAddress])
    case powerSnapshots([String])
    case powerSnapshot(String)
    case powerVerify
    case powerEnsureUnchanged
    case powerEnsureCurrentMatchesAny
    case powerAuthorization
    case powerApply(PowerSettingSnapshot)
    case powerRestore([PowerSettingSnapshot])
    case powerRestorePreservingExternalChanges
    case journalRead(URL)
    case journalPersist(URL, [PreferenceSnapshot], [PreferenceSnapshot])
    case journalRemove(URL)

    var description: String {
        switch self {
        case .preferenceSnapshots: return "preference.snapshots"
        case .preferenceVerify: return "preference.verify"
        case .preferenceEnsureUnchanged: return "preference.ensureUnchanged"
        case .preferenceEnsureCurrentMatchesAny:
            return "preference.ensureCurrentMatchesAny"
        case .preferenceRead: return "preference.readValues"
        case .preferenceApply(let address, let value):
            let renderedValue = value?.displayValue ?? "nil"
            return "preference.apply(\(address.displayPath)=\(renderedValue))"
        case .preferenceRestore: return "preference.restore"
        case .preferenceRestorePreservingExternalChanges:
            return "preference.restorePreservingExternalChanges"
        case .restart(let names):
            return "restart(\(names.joined(separator: ",")))"
        case .managementRead: return "management.forcedAddresses"
        case .powerSnapshots: return "power.snapshots"
        case .powerSnapshot(let key): return "power.snapshot(\(key))"
        case .powerVerify: return "power.verify"
        case .powerEnsureUnchanged: return "power.ensureUnchanged"
        case .powerEnsureCurrentMatchesAny: return "power.ensureCurrentMatchesAny"
        case .powerAuthorization: return "power.authorized"
        case .powerApply(let snapshot): return "power.apply(\(snapshot.key))"
        case .powerRestore: return "power.restore"
        case .powerRestorePreservingExternalChanges:
            return "power.restorePreservingExternalChanges"
        case .journalRead(let url): return "journal.read(\(url.lastPathComponent))"
        case .journalPersist(let url, _, _):
            return "journal.persist(\(url.lastPathComponent))"
        case .journalRemove(let url): return "journal.remove(\(url.lastPathComponent))"
        }
    }

    var isExternalMutationOrTransactionEffect: Bool {
        switch self {
        case .preferenceApply, .preferenceRestore,
                .preferenceRestorePreservingExternalChanges, .restart,
                .powerAuthorization, .powerApply, .powerRestore,
                .powerRestorePreservingExternalChanges,
                .journalPersist, .journalRemove:
            return true
        default:
            return false
        }
    }
}

private final class RecordingDependencyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RecordingDependencyEvent] = []

    func append(_ event: RecordingDependencyEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func checkpoint() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func events(since checkpoint: Int) -> [RecordingDependencyEvent] {
        lock.lock()
        defer { lock.unlock() }
        guard checkpoint < storage.count else { return [] }
        return Array(storage[checkpoint...])
    }
}

private final class RecordingPreferenceExecutor: PreferenceExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PreferenceAddress: PreferenceValue]
    private let allowedMutations: [(PreferenceAddress, PreferenceValue?)]
    private let allowedRestores: [PreferenceSnapshot]
    private let failingApplyAddress: PreferenceAddress?
    private let log: RecordingDependencyLog

    init(
        values: [PreferenceAddress: PreferenceValue],
        allowedMutations: [(PreferenceAddress, PreferenceValue?)],
        allowedRestores: [PreferenceSnapshot] = [],
        failingApplyAddress: PreferenceAddress? = nil,
        log: RecordingDependencyLog
    ) {
        self.values = values
        self.allowedMutations = allowedMutations
        self.allowedRestores = allowedRestores
        self.failingApplyAddress = failingApplyAddress
        self.log = log
    }

    func snapshots(for addresses: [PreferenceAddress]) throws -> [PreferenceSnapshot] {
        log.append(.preferenceSnapshots(addresses))
        lock.lock()
        defer { lock.unlock() }
        return addresses.map { PreferenceSnapshot(address: $0, value: values[$0]) }
    }

    func verify(_ expected: [PreferenceSnapshot]) throws {
        log.append(.preferenceVerify(expected))
        let current = currentSnapshots(for: expected.map(\.address))
        guard snapshotsMatch(expected, current) else {
            throw PreferenceExecutorError.verification("内存偏好验证失败")
        }
    }

    func ensureUnchanged(since expected: [PreferenceSnapshot]) throws {
        log.append(.preferenceEnsureUnchanged(expected))
        let current = currentSnapshots(for: expected.map(\.address))
        guard snapshotsMatch(expected, current) else {
            throw PreferenceExecutorError.conflict("内存偏好出现外部冲突")
        }
    }

    func ensureCurrentMatchesAny(
        _ allowedStates: [[PreferenceSnapshot]],
        operation: LocalizedText
    ) throws {
        log.append(.preferenceEnsureCurrentMatchesAny)
        let addresses = Array(Set(allowedStates.flatMap { $0.map(\.address) }))
        let current = currentSnapshots(for: addresses)
        for snapshot in current {
            let allowedValues = allowedStates.flatMap { state in
                state.filter { $0.address == snapshot.address }.map(\.value)
            }
            guard allowedValues.contains(where: {
                optionalValuesMatch($0, snapshot.value)
            }) else {
                throw PreferenceExecutorError.conflict("内存偏好不允许\(operation)")
            }
        }
    }

    func readValues(
        for addresses: [PreferenceAddress]
    ) throws -> [PreferenceAddress: PreferenceValue] {
        log.append(.preferenceRead(addresses))
        lock.lock()
        defer { lock.unlock() }
        var result: [PreferenceAddress: PreferenceValue] = [:]
        for address in addresses {
            if let value = values[address] { result[address] = value }
        }
        return result
    }

    func apply(_ mutation: PreferenceMutation) throws {
        log.append(.preferenceApply(mutation.address, mutation.value))
        if mutation.address == failingApplyAddress {
            throw CheckFailure.failed("模拟第二键写入失败")
        }
        guard allowedMutations.contains(where: {
            $0.0 == mutation.address && optionalValuesMatch($0.1, mutation.value)
        }) else {
            throw CheckFailure.failed("内存执行器拒绝未声明的偏好 mutation")
        }
        lock.lock()
        if let value = mutation.value {
            values[mutation.address] = value
        } else {
            values.removeValue(forKey: mutation.address)
        }
        lock.unlock()
    }

    func restore(_ snapshots: [PreferenceSnapshot]) throws {
        log.append(.preferenceRestore(snapshots))
        try restoreAllowedSnapshots(snapshots)
    }

    func restorePreservingExternalChanges(
        _ target: [PreferenceSnapshot],
        whenCurrentMatches allowedStates: [[PreferenceSnapshot]]
    ) throws -> [PreferenceAddress] {
        log.append(.preferenceRestorePreservingExternalChanges)
        try ensureCurrentMatchesAny(allowedStates, operation: "回滚")
        try restoreAllowedSnapshots(target)
        return []
    }

    private func restoreAllowedSnapshots(_ snapshots: [PreferenceSnapshot]) throws {
        guard !allowedRestores.isEmpty, snapshots.allSatisfy({ allowedRestores.contains($0) }) else {
            throw CheckFailure.failed("内存执行器拒绝未声明的 restore")
        }
        lock.lock()
        defer { lock.unlock() }
        for snapshot in snapshots {
            if let value = snapshot.value { values[snapshot.address] = value }
            else { values.removeValue(forKey: snapshot.address) }
        }
    }

    func value(for address: PreferenceAddress) -> PreferenceValue? {
        lock.lock()
        defer { lock.unlock() }
        return values[address]
    }

    private func currentSnapshots(
        for addresses: [PreferenceAddress]
    ) -> [PreferenceSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return addresses.map { PreferenceSnapshot(address: $0, value: values[$0]) }
    }

    private func snapshotsMatch(
        _ expected: [PreferenceSnapshot],
        _ current: [PreferenceSnapshot]
    ) -> Bool {
        let currentByAddress = Dictionary(
            uniqueKeysWithValues: current.map { ($0.address, $0.value) }
        )
        return expected.allSatisfy { snapshot in
            optionalValuesMatch(snapshot.value, currentByAddress[snapshot.address] ?? nil)
        }
    }

    private func optionalValuesMatch(
        _ lhs: PreferenceValue?,
        _ rhs: PreferenceValue?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let left), .some(let right)): return left.matches(right)
        default: return false
        }
    }
}

private final class RecordingRestarter: ProcessRestarting, @unchecked Sendable {
    private let log: RecordingDependencyLog

    init(log: RecordingDependencyLog) {
        self.log = log
    }

    func restart(_ processNames: [String]) {
        log.append(.restart(processNames))
    }
}

private struct RecordingManagementProvider: PreferenceManagementProviding {
    let log: RecordingDependencyLog
    var forced: Set<PreferenceAddress> = []
    var shouldFail = false

    func forcedAddresses(
        for addresses: [PreferenceAddress]
    ) throws -> Set<PreferenceAddress> {
        log.append(.managementRead(addresses))
        if shouldFail { throw CheckFailure.failed("模拟管理状态无法确认") }
        return forced.intersection(addresses)
    }
}

private final class FailClosedPowerExecutor: PowerSettingsExecuting, @unchecked Sendable {
    private let log: RecordingDependencyLog

    init(log: RecordingDependencyLog) {
        self.log = log
    }

    func snapshots(for keys: [String]) throws -> [PowerSettingSnapshot] {
        log.append(.powerSnapshots(keys))
        return []
    }

    func snapshot(for key: String) throws -> PowerSettingSnapshot? {
        log.append(.powerSnapshot(key))
        return nil
    }

    func verify(_ expected: [PowerSettingSnapshot]) throws {
        log.append(.powerVerify)
        throw CheckFailure.failed("内存电源执行器拒绝 verify")
    }

    func ensureUnchanged(since expected: [PowerSettingSnapshot]) throws {
        log.append(.powerEnsureUnchanged)
        throw CheckFailure.failed("内存电源执行器拒绝 ensureUnchanged")
    }

    func ensureCurrentMatchesAny(
        _ allowedStates: [[PowerSettingSnapshot]],
        operation: LocalizedText
    ) throws {
        log.append(.powerEnsureCurrentMatchesAny)
        throw CheckFailure.failed("内存电源执行器拒绝 ensureCurrentMatchesAny")
    }

    func authorized(
        _ operation: (PowerAuthorizationContext) throws -> Void
    ) throws {
        log.append(.powerAuthorization)
        throw CheckFailure.failed("内存电源执行器拒绝授权")
    }

    func apply(
        _ snapshot: PowerSettingSnapshot,
        authorization: PowerAuthorizationContext
    ) throws {
        log.append(.powerApply(snapshot))
        throw CheckFailure.failed("内存电源执行器拒绝写入")
    }

    func restore(
        _ snapshots: [PowerSettingSnapshot],
        authorization: PowerAuthorizationContext
    ) throws {
        log.append(.powerRestore(snapshots))
        throw CheckFailure.failed("内存电源执行器拒绝恢复")
    }

    func restorePreservingExternalChanges(
        _ target: [PowerSettingSnapshot],
        whenCurrentMatches allowedStates: [[PowerSettingSnapshot]],
        authorization: PowerAuthorizationContext
    ) throws -> [String] {
        log.append(.powerRestorePreservingExternalChanges)
        throw CheckFailure.failed("内存电源执行器拒绝冲突感知恢复")
    }
}

private final class RecordingJournal: PreferenceTransactionJournaling, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [URL: UndoRecord] = [:]
    private let expectedURL: URL
    private let throwOnRead: Bool
    private let log: RecordingDependencyLog

    init(
        expectedURL: URL,
        throwOnRead: Bool = false,
        log: RecordingDependencyLog
    ) {
        self.expectedURL = expectedURL
        self.throwOnRead = throwOnRead
        self.log = log
    }

    func persist(_ record: UndoRecord, to url: URL) throws {
        log.append(.journalPersist(url, record.before, record.after))
        guard url == expectedURL else {
            throw CheckFailure.failed("内存 journal 拒绝非测试 URL")
        }
        lock.lock()
        records[url] = record
        lock.unlock()
    }

    func read(from url: URL) throws -> UndoRecord? {
        log.append(.journalRead(url))
        guard url == expectedURL else {
            throw CheckFailure.failed("内存 journal 拒绝非测试 URL")
        }
        if throwOnRead {
            throw CheckFailure.failed("模拟 journal 内容无法读取")
        }
        lock.lock()
        defer { lock.unlock() }
        return records[url]
    }

    @discardableResult
    func remove(at url: URL) -> Bool {
        log.append(.journalRemove(url))
        guard url == expectedURL else { return false }
        lock.lock()
        records.removeValue(forKey: url)
        lock.unlock()
        return true
    }
}

/// A helper can time out after accepting a write. Successful compensation does
/// not prove that helper has exited, so this double verifies WAL retention.
private final class TimedOutPowerExecutor: PowerSettingsExecuting, @unchecked Sendable {
    private let log: RecordingDependencyLog
    private let before = PowerSettingSnapshot(
        key: "ttyskeepawake", values: [PowerSourceValue(source: .charger, value: 1)]
    )

    init(log: RecordingDependencyLog) { self.log = log }

    func snapshots(for keys: [String]) throws -> [PowerSettingSnapshot] {
        log.append(.powerSnapshots(keys))
        return keys.contains(before.key) ? [before] : []
    }
    func snapshot(for key: String) throws -> PowerSettingSnapshot? {
        log.append(.powerSnapshot(key))
        return key == before.key ? before : nil
    }
    func verify(_ expected: [PowerSettingSnapshot]) throws {
        log.append(.powerVerify)
        guard expected == [before] else {
            throw CheckFailure.failed("超时替身只允许校验补偿后的原值")
        }
    }
    func ensureUnchanged(since expected: [PowerSettingSnapshot]) throws {
        log.append(.powerEnsureUnchanged)
        guard expected == [before] else {
            throw CheckFailure.failed("超时替身预检基线不一致")
        }
    }
    func ensureCurrentMatchesAny(
        _ allowedStates: [[PowerSettingSnapshot]], operation: LocalizedText
    ) throws {
        log.append(.powerEnsureCurrentMatchesAny)
        throw CheckFailure.failed("超时替身拒绝非测试恢复")
    }
    func authorized(_ operation: (PowerAuthorizationContext) throws -> Void) throws {
        log.append(.powerAuthorization)
        try operation(PowerAuthorizationContext(reference: nil))
    }
    func apply(_ snapshot: PowerSettingSnapshot, authorization: PowerAuthorizationContext) throws {
        log.append(.powerApply(snapshot))
        guard snapshot.key == before.key && snapshot.values.map(\.value) == [0] else {
            throw CheckFailure.failed("超时替身收到错误写入")
        }
        throw PowerSettingsError.privilegedTimeout("recording pmset")
    }
    func restore(_ snapshots: [PowerSettingSnapshot], authorization: PowerAuthorizationContext) throws {
        log.append(.powerRestore(snapshots))
        throw CheckFailure.failed("超时替身拒绝非预期直接恢复")
    }
    func restorePreservingExternalChanges(
        _ target: [PowerSettingSnapshot],
        whenCurrentMatches allowedStates: [[PowerSettingSnapshot]],
        authorization: PowerAuthorizationContext
    ) throws -> [String] {
        log.append(.powerRestorePreservingExternalChanges)
        guard target == [before] else {
            throw CheckFailure.failed("超时替身补偿目标不一致")
        }
        return []
    }
}

private final class InMemoryApplicationState: ApplicationStateStoring {
    private var values: [String: Any] = [:]
    private(set) var writtenKeys: [String] = []

    func bool(forKey defaultName: String) -> Bool {
        (values[defaultName] as? NSNumber)?.boolValue ??
            (values[defaultName] as? Bool) ?? false
    }

    func dictionary(forKey defaultName: String) -> [String: Any]? {
        values[defaultName] as? [String: Any]
    }

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func data(forKey defaultName: String) -> Data? {
        values[defaultName] as? Data
    }

    func set(_ value: Any?, forKey defaultName: String) {
        writtenKeys.append(defaultName)
        if let value {
            values[defaultName] = value
        } else {
            values.removeValue(forKey: defaultName)
        }
    }

    func removeObject(forKey defaultName: String) {
        values.removeValue(forKey: defaultName)
    }
}

private struct FixedTimeProvider: TimeProviding {
    func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }
}

private struct FixedIdentifierProvider: IdentifierProviding {
    func makeIdentifier() -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }
}

@main
struct TerminalSettingsChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure.failed(message) }
    }

    @MainActor
    static func main() {
        do {
            try runChecks()
        } catch {
            let message = "TerminalSettings checks failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func runChecks() throws {
        try checkCatalog()
        try checkLocalizationContracts()
        try checkPrecisionEnhancementModels()
        try checkRecoveryPlanningContracts()
        try checkUndoEncoding()
        try checkRecordingCustomizationContracts()
        try checkRecordingPrecisionEnhancements()
        try checkPrivilegedTimeoutRetainsJournal(language: .simplifiedChinese)
        try checkPrivilegedTimeoutRetainsJournal(language: .english)
        try checkUnreadableJournalFailClosedContract()
        let contractOnly = ProcessInfo.processInfo.environment[
            "TERMINAL_SETTINGS_CONTRACT_ONLY"
        ] == "1"
        if contractOnly {
            print("TerminalSettings contract checks passed")
        } else {
            try checkCustomizationStoreSurface()
            try checkExecutorAndSnapshots()
            try checkPowerSettingsParsing()
            print("TerminalSettings checks passed")
        }
    }

    private static func localizationTestBundle() throws -> Bundle {
        guard let path = ProcessInfo.processInfo.environment["TERMINAL_SETTINGS_TEST_RESOURCE_BUNDLE"],
              let bundle = Bundle(path: path) else {
            throw CheckFailure.failed("缺少显式注入的隔离语言资源 Bundle")
        }
        return bundle
    }

    private static func localizationTestResources() throws -> LocalizationResources {
        LocalizationResources(bundle: try localizationTestBundle())
    }

    @MainActor
    private static func checkLocalizationContracts() throws {
        let bundle = try localizationTestBundle()
        let resources = LocalizationResources(bundle: bundle)
        let chineseKeys = resources.keys(for: .simplifiedChinese)
        try require(chineseKeys.count >= 500 && chineseKeys == resources.keys(for: .english),
                    "中英文资源键不完整或不一致")
        let placeholderPattern = try NSRegularExpression(pattern: "\\{[0-9]+\\}")
        func placeholders(_ text: String) -> [String] {
            placeholderPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for key in chineseKeys {
            let zh = resources.string(key: key, language: .simplifiedChinese)!
            let en = resources.string(key: key, language: .english)!
            try require((!zh.isEmpty && !en.isEmpty) || key == LocalizedText.key(for: ""), "存在意外空翻译")
            try require(placeholders(zh) == placeholders(en), "翻译占位符不一致：\(key)")
        }
        for language in [AppLanguage.simplifiedChinese, .english] {
            let url = bundle.resourceURL!.appendingPathComponent(language.rawValue + ".lproj/Localizable.strings")
            let contents = try String(contentsOf: url, encoding: .utf8)
            let lines = contents.split(separator: "\n").filter { $0.hasPrefix("\"text.") }
            try require(lines.count == resources.keys(for: language).count, "资源存在重复键或无效行")
        }
        let han = try NSRegularExpression(pattern: "[\\x{3400}-\\x{9FFF}]")
        func checkText(_ text: LocalizedText) throws {
            let en = text.rendered(language: .english, resources: resources)
            try require(han.firstMatch(in: en, range: NSRange(en.startIndex..., in: en)) == nil,
                        "英文显示仍包含未翻译汉字：\(en)")
            try require(!en.contains("LocalizedText(") && !en.contains("Part.message"), "界面泄漏了文本模型描述")
        }
        for category in SettingsCategory.allCases {
            try checkText(category.title); try checkText(category.subtitle)
        }
        for item in PreferenceCatalog.items {
            for text in [item.title, item.detail, item.effectHint, item.evidence.title,
                         item.source.detailLabel, item.recovery.detail, item.recovery.actionTitle] {
                try checkText(text)
            }
            if let note = item.stability.note { try checkText(note) }
            if let note = item.source.note { try checkText(note) }
            if let system = item.source.systemSettings {
                try checkText(system.path); try checkText(system.note)
            }
            if case .choice(let choice) = item.control {
                for option in choice.options { try checkText(option.title) }
            }
            if let numeric = item.numericConfiguration {
                try checkText(numeric.detail); try checkText(numeric.presetSummary)
                for parameter in numeric.parameters {
                    try checkText(parameter.title); try checkText(parameter.detail)
                    try checkText(parameter.rangeLabel)
                    for special in parameter.specialValues { try checkText(special.title) }
                    for preset in parameter.presets { try checkText(preset.title) }
                }
            }
        }
        try require(SettingsCategory.overview.title.rendered(language: .english, resources: resources) == "Overview", "英文概览翻译错误")
        try require((L("版本 ") + "1.9.0").rendered(language: .english, resources: resources) == "Version 1.9.0", "翻译丢失了前缀尾部空格")
        try require(L("；").rendered(language: .english, resources: resources) == "; ", "翻译丢失了列表分隔空格")
        try require(SettingsCategory.overview.title.rendered(language: .simplifiedChinese, resources: resources) == "概览", "原有中文概览改变")
        for (preferred, expected) in [(["zh-Hans-CN"], AppLanguage.simplifiedChinese), (["en-US"], .english), (["de-DE"], .english), (["zh-Hant-TW"], .english), ([], .english)] {
            try require(AppLanguage.system.resolved(preferredLanguages: preferred) == expected, "跟随系统回退规则错误")
        }
        let state = InMemoryApplicationState()
        let language = AppLanguageStore(state: state, resources: resources, preferredLanguages: { ["en-US"] })
        try require(language.choice == .system && language.resolved == .english && state.writtenKeys.isEmpty,
                    "默认语言读取不应写入应用或系统状态")
        let unknownState = InMemoryApplicationState()
        unknownState.set("future-language", forKey: AppLanguageStore.preferenceKey)
        let unknownCount = unknownState.writtenKeys.count
        let unknown = AppLanguageStore(state: unknownState, resources: resources, preferredLanguages: { ["zh-Hans"] })
        try require(unknown.choice == .system && unknown.resolved == .simplifiedChinese && unknownState.writtenKeys.count == unknownCount, "未知语言值应只读回退")

        let item = PreferenceCatalog.items.first { $0.id == "dock.fastAnimation" }!
        let disclosure = PreferenceDisplayText.disclosureLabel(title: item.title, action: L("展开详情与命令"))
        try require(disclosure.rendered(language: .english, resources: resources) == "Try a shorter Dock auto-hide animation: Show details and commands", "折叠按钮 AX 标签泄漏文本模型或未翻译")
        let parameter = item.numericConfiguration!.parameters[0]
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TerminalSettingsLanguage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = RecordingDependencyLog()
        let journal = RecordingJournal(expectedURL: directory.appendingPathComponent("pending-preference-transaction.json"), log: log)
        let store = PreferencesStore(
            executor: RecordingPreferenceExecutor(values: [:], allowedMutations: [], log: log),
            restarter: RecordingRestarter(log: log), managementProvider: RecordingManagementProvider(log: log),
            powerExecutor: FailClosedPowerExecutor(log: log), journal: journal, appState: state,
            timeProvider: FixedTimeProvider(), identifierProvider: FixedIdentifierProvider(),
            undoStorageURL: directory.appendingPathComponent("last-undo.json")
        )
        store.prepareCustomizationModeTest(item, parentEnabled: true)
        store.setCustomizationEnabled(item, enabled: true)
        store.setCustomizationDraft(item, parameter: parameter, value: 0.321)
        store.setCustomizationInputError(item, parameter: parameter, message: L("请输入有效数值"))
        store.textDrafts["screenshot.name"] = "原文 {0} & $HOME"
        let valuesBefore = store.customizationDrafts, errorsBefore = store.customizationInputErrors
        let commandsBefore = PreferenceCatalog.items.flatMap { store.previewCommands(for: $0).map { $0.1 } }
        let modeBefore = store.customizationModes, noticeBefore = store.notice?.message, undoBefore = store.undoSummary
        let checkpoint = log.checkpoint(), writesBefore = state.writtenKeys.count
        for index in 0..<100 { language.select(index.isMultiple(of: 2) ? .simplifiedChinese : .english) }
        try require(log.events(since: checkpoint).isEmpty, "切换语言触发了读取、写入、进程、授权或日志操作")
        try require(state.writtenKeys.dropFirst(writesBefore).allSatisfy { $0 == AppLanguageStore.preferenceKey }, "语言开关改写了其他应用状态")
        try require(valuesBefore == store.customizationDrafts && errorsBefore == store.customizationInputErrors && modeBefore == store.customizationModes && noticeBefore == store.notice?.message && undoBefore == store.undoSummary, "切换语言丢失了草稿、模式、提示或撤销")
        try require(store.textDrafts["screenshot.name"] == "原文 {0} & $HOME", "用户原文被翻译或插值")
        try require(commandsBefore == PreferenceCatalog.items.flatMap { store.previewCommands(for: $0).map { $0.1 } }, "中英文实际命令不一致")
        try require(language.text(store.customizationInputErrors[item.id]![parameter.id]!) == "Enter a valid number", "缓存错误未随语言即时改变")
        try require(PreferenceCatalog.search("Dock", resources: resources).contains { $0.id == item.id } && PreferenceCatalog.search("程序坞", resources: resources).contains { $0.id == item.id }, "搜索未同时索引中英文")
        try require(PreferenceCatalog.search("autohide-time-modifier", resources: resources).map(\.id) == [item.id], "技术键搜索有遗漏或重复")
        let diagnostic = "原始诊断 {0} defaults $HOME"
        let message = PreferenceExecutorError.command("defaults read X", LocalizedText(verbatim: diagnostic)).displayMessage
        try require(message.rendered(language: .english, resources: resources) == "Command failed: defaults read X\n" + diagnostic, "原始输出被二次解释或翻译")
        for regionID in ["en_US", "zh_CN", "de_DE"] {
            let region = Locale(identifier: regionID)
            let input = regionID == "de_DE" ? "0,001" : "0.001"
            try require(parameter.displayValue(0.001, region: region).rendered(language: .english, resources: resources) == input, "实际数值参数未使用系统区域格式")
            try require(RegionalNumberInput.parse(input, region: region) == 0.001, "区域小数解析错误")
            try require(RegionalNumberInput.parse("0", region: region) == 0 && RegionalNumberInput.parse("3600", region: region) == 3600, "整数或特殊 0 被改变")
            try require(RegionalNumberInput.parse("bad", region: region) == nil, "非法输入被接受")
            for raw in ["NaN", "Inf", "-Inf"] {
                let parsed = RegionalNumberInput.parse(raw, region: region)
                try require(parsed == nil || parameter.exactInputError(for: parsed!) != nil, "非有限值被接受")
            }
            let numericText = L("\(0.001)")
            try require(numericText.rendered(language: .english, resources: resources, region: region) == numericText.rendered(language: .simplifiedChinese, resources: resources, region: region), "界面语言改变了区域数字显示")
        }
        try require(PreferenceValue.float(0.001).defaultsArguments == ["-float", "0.001"], "命令小数格式改变")
        if case .choice(let tooltip) = PreferenceCatalog.items.first(where: { $0.id == "windows.tooltipDelay" })!.control {
            let fast = tooltip.options.first { $0.id == "fast" }!
            try require(fast.title.rendered(language: .english, resources: resources, region: Locale(identifier: "de_DE")) == "0,1 s" && fast.value == .integer(100), "数值预设应随区域显示但保持原始执行值")
        }

        let address = item.allAddresses[0]
        let old = UndoRecord(title: "旧撤销原始标题", before: [.init(address: address, value: nil)], after: [.init(address: address, value: .float(0.18))], restartProcesses: ["Dock"], createdAt: Date(timeIntervalSince1970: 0))
        let action = L("已应用“\(item.title)”的自定义值")
        let new = UndoRecord(title: action.source, displayAction: action, before: old.before, after: old.after, restartProcesses: old.restartProcesses, createdAt: old.createdAt)
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let oldData = try encoder.encode(old), newData = try encoder.encode(new)
        try require(old.localizedTitle(resources: resources).rendered(language: .english, resources: resources) == old.title, "旧标题被改写")
        try require(new.localizedTitle(resources: resources).rendered(language: .english, resources: resources) == "Applied custom values for “Try a shorter Dock auto-hide animation”", "新记录没有延迟翻译")
        var json = try JSONSerialization.jsonObject(with: newData) as! [String: Any]
        json["displayAction"] = ["unknown": true]
        let damaged = try decoder.decode(UndoRecord.self, from: JSONSerialization.data(withJSONObject: json))
        try require(damaged.before == old.before && damaged.title == new.title && damaged.displayAction == nil, "损坏显示字段阻断恢复读取")
        let unknownAction = LocalizedText(part: .message(key: "future.action", fallback: "future", arguments: []))
        let future = UndoRecord(title: old.title, displayAction: unknownAction, before: old.before, after: old.after, restartProcesses: old.restartProcesses, createdAt: old.createdAt)
        try require(future.localizedTitle(resources: resources).rendered(language: .english, resources: resources) == old.title, "未知动作未回退原始标题")
        let decodedOld = try decoder.decode(UndoRecord.self, from: oldData)
        try require(decodedOld.displayAction == nil, "旧记录读取不兼容")
        struct LegacyUndo: Decodable { let title: String; let before: [PreferenceSnapshot]; let after: [PreferenceSnapshot] }
        let legacy = try decoder.decode(LegacyUndo.self, from: newData)
        try require(legacy.title == new.title && legacy.before == old.before && legacy.after == old.after, "新增显示字段破坏旧读取器")
        print("Localization contracts passed: \(chineseKeys.count) resource keys; bilingual catalog, zero-effect switching, region formats, legacy undo, and verbatim diagnostics")
    }

    private static func checkCatalog() throws {
        let items = PreferenceCatalog.items
        try require(items.count == 40, "目录数量应为 40，实际为 \(items.count)")
        try require(Set(items.map(\.id)).count == items.count, "目录中存在重复 ID")
        let categoryCounts = Dictionary(grouping: items, by: \.category).mapValues(\.count)
        try require(categoryCounts[.dock] == 13, "程序坞目录数量应为 13")
        try require(categoryCounts[.finder] == 6, "访达目录数量应为 6")
        try require(categoryCounts[.screenshots] == 4, "截屏目录数量应为 4")
        try require(categoryCounts[.trackpad] == 1, "触控板目录数量应为 1")
        try require(categoryCounts[.keyboard] == 2, "键盘目录数量应为 2")
        try require(categoryCounts[.windows] == 7, "窗口目录数量应为 7")
        try require(categoryCounts[.system] == 4, "系统目录数量应为 4")
        try require(categoryCounts[.advanced] == 3, "高级目录数量应为 3")
        let sourceCounts = Dictionary(grouping: items, by: { $0.source.exposure })
            .mapValues(\.count)
        try require(sourceCounts[.terminalOnly] == 34, "仅终端来源数量应为 34")
        try require(sourceCounts[.systemSettingsEnhancement] == 4, "系统设置增强数量应为 4")
        try require(sourceCounts[.systemSettingsMirror] == 2, "系统设置镜像数量应为 2")
        try require(
            Set(items.filter { $0.source.exposure == .systemSettingsEnhancement }.map(\.id)) ==
                Set(["dock.suckEffect", "keyboard.ultraFast", "dock.iconSizes", "system.screensaverIdle"]),
            "系统设置增强映射不符合当前目录审计"
        )
        try require(
            Set(items.filter { $0.source.exposure == .systemSettingsMirror }.map(\.id)) ==
                Set(["dock.noLaunchAnimation", "dock.disableLegacyLaunchpadPinchGesture"]),
            "系统设置镜像映射不符合当前目录审计"
        )
        try require(
            items.allSatisfy {
                !$0.source.exposure.label.isEmpty &&
                    ($0.source.exposure == .terminalOnly || $0.source.systemSettings != nil)
            },
            "镜像与增强项目必须提供系统设置关系，所有项目必须提供来源标签"
        )
        try require(
            items.filter { $0.source.exposure != .terminalOnly }.allSatisfy {
                if case .restoreBaseline = $0.recovery.strategy { return true }
                return false
            },
            "所有系统设置增强或镜像项目都必须恢复接管前值"
        )
        guard let legacyGesture = items.first(where: {
            $0.id == "dock.disableLegacyLaunchpadPinchGesture"
        }), let legacyCoverage = legacyGesture.source.systemSettings?.coverage else {
            throw CheckFailure.failed("旧版 Launchpad 镜像缺少系统设置关系")
        }
        if case .related = legacyCoverage {
            // Historical mirror only; it is not Tahoe's confirmed equivalent.
        } else {
            throw CheckFailure.failed("旧版 Launchpad 项不得声称为 Tahoe 等价入口")
        }
        try require(
            items.filter {
                if case .deleteExplicit = $0.recovery.strategy { return true }
                return false
            }.allSatisfy {
                $0.recovery.actionTitle == "删除当前显式值" &&
                    $0.recovery.detail.contains("不论")
            },
            "删除型恢复必须明确可能删除由其他工具创建的当前用户显式值"
        )
        try require(
            items.allSatisfy { !$0.allAddresses.isEmpty || $0.privilegedKey != nil },
            "每项设置必须具有偏好地址或受控管理员能力"
        )
        try require(items.allSatisfy { !$0.compatibility.verifiedDate.isEmpty }, "缺少验证日期")
        try require(items.allSatisfy { !$0.compatibility.verifiedOSVersion.isEmpty }, "缺少验证系统版本")
        try require(items.allSatisfy { !$0.evidence.title.isEmpty }, "缺少依据说明")
        let experimentalItems = items.filter { $0.caution == .compatibility }
        let unstableItems = items.filter { $0.stability.isUnstable }
        try require(experimentalItems.count == 17, "实验性项目数量应为 17")
        try require(
            Set(experimentalItems.map(\.id)) == Set(unstableItems.map(\.id)),
            "语义或效果不确定的项目必须同时标记为实验性与不稳定"
        )
        try require(
            unstableItems.allSatisfy {
                !($0.stability.note ?? "").source
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            },
            "每个不稳定项目必须提供具体注释"
        )
        try require(
            items.allSatisfy { item in
                item.numericConfiguration?.parameters.allSatisfy {
                    $0.range.contains($0.presetValue) && $0.step > 0 &&
                    item.allAddresses.contains($0.address)
                } ?? true
            },
            "自定义参数必须具有有效范围、步进和恢复地址"
        )
        let allCustomizationParameters = items
            .compactMap(\.numericConfiguration)
            .flatMap(\.parameters)
        try require(
            allCustomizationParameters.allSatisfy { parameter in
                let displayedResolution = pow(10, -Double(parameter.precision))
                return abs(parameter.step - displayedResolution) < 0.000_000_1
            },
            "所有滑块都必须使用当前显示精度可表达的最小分度"
        )
        try require(
            allCustomizationParameters.allSatisfy { parameter in
                switch parameter.storage {
                case .integer:
                    return abs(parameter.step * parameter.storageScale - 1) < 0.000_000_1
                case .float:
                    return (parameter.precision == 3 &&
                        abs(parameter.step - 0.001) < 0.000_000_1) ||
                        (["tileSize", "largeSize"].contains(parameter.id) &&
                         parameter.precision == 0 && parameter.step == 1)
                }
            },
            "整数滑块每格必须只改变一个存储单位，浮点滑块使用已确认最小分度"
        )
        let continuousTrackParameters = allCustomizationParameters.filter(
            \.usesContinuousSliderTrack
        )
        try require(
            continuousTrackParameters.count == 4 &&
                continuousTrackParameters.filter { $0.discreteValueCount == 2_001 && $0.step == 0.001 }.count == 3 &&
                continuousTrackParameters.contains { $0.id == "idleTime" && $0.discreteValueCount == 3_600 && $0.step == 1 },
            "四个高密度滑块必须使用连续轨道并保留各自量化单位"
        )
        try require(
            allCustomizationParameters
                .filter { !$0.usesContinuousSliderTrack }
                .allSatisfy {
                    $0.discreteValueCount <=
                        NumericPreferenceParameter.maximumSteppedSliderValueCount
                },
            "低基数 stepped Slider 不得超过枚举阈值"
        )
        try require(
            items.allSatisfy { item in
                guard let parameters = item.numericConfiguration?.parameters else { return true }
                return Set(parameters.map(\.id)).count == parameters.count &&
                    Set(parameters.map(\.address)).count == parameters.count
            },
            "同一功能项的自定义参数 ID 与偏好地址必须唯一"
        )

        let supported = [1, 2].allSatisfy { patch in
            items.allSatisfy {
                $0.support(for: OperatingSystemVersion(
                    majorVersion: 26,
                    minorVersion: 6,
                    patchVersion: patch
                )) == .supported
            }
        }
        try require(supported, "目录应标记为支持验证环境")

        let laterPatchIsUnverified = items.allSatisfy { item in
            if case .unverified(let note) = item.support(for: OperatingSystemVersion(
                majorVersion: 26,
                minorVersion: 6,
                patchVersion: 3
            )) {
                return note.contains("macOS 26.6.3") && note.contains("macOS 26.6.2")
            }
            return false
        }
        try require(
            laterPatchIsUnverified,
            "晚于最后验证补丁版本的系统必须标记为未验证"
        )

        let nextMajorIsUnverified = items.allSatisfy { item in
            if case .unverified = item.support(for: OperatingSystemVersion(
                majorVersion: 27,
                minorVersion: 0,
                patchVersion: 0
            )) {
                return true
            }
            return false
        }
        try require(nextMajorIsUnverified, "后续主版本必须标记为未验证")
        try require(items.allSatisfy { item in
            if case .unverified = item.support(for: OperatingSystemVersion(
                majorVersion: 26, minorVersion: 7, patchVersion: 0
            )) { return true }
            return false
        }, "后续次版本必须标记为未验证")

        let desktopServices = items
            .filter { ["finder.noNetworkDSStore", "finder.noUSBDSStore"].contains($0.id) }
            .flatMap(\.allAddresses)
        try require(
            desktopServices.allSatisfy { $0.domain == "com.apple.desktopservices" },
            ".DS_Store 设置必须使用 com.apple.desktopservices"
        )

        let menuBar = items.first { $0.id == "system.compactMenuBar" }
        try require(menuBar != nil, "缺少菜单栏紧凑间距设置")
        try require(
            menuBar?.allAddresses.allSatisfy { $0.hostScope == .currentHost } == true,
            "菜单栏间距必须使用当前主机偏好域"
        )

        guard let appsGesture = items.first(where: { $0.id == "dock.disableAppsPinchGesture" }) else {
            throw CheckFailure.failed("缺少 Tahoe 应用程序捏合手势设置")
        }
        guard case .toggle(let appsGesturePreference) = appsGesture.control else {
            throw CheckFailure.failed("应用程序捏合手势必须使用开关控件")
        }
        try require(
            appsGesturePreference.readAddress == PreferenceAddress(
                domain: "com.apple.dock",
                key: "showSpotlightGestureEnabled"
            ),
            "应用程序捏合手势使用了错误的 Dock 偏好键"
        )
        try require(
            appsGesturePreference.enabledValue == .bool(false),
            "开启“关闭捏合”时必须写入 false"
        )
        try require(
            appsGesture.support(
                for: OperatingSystemVersion(majorVersion: 25, minorVersion: 0, patchVersion: 0)
            ) == .unsupported(L("需要 macOS \(26) 或更高版本")),
            "应用程序捏合手势不应标记为支持 macOS 25"
        )

        guard let dockAnimation = items.first(where: { $0.id == "dock.fastAnimation" }) else {
            throw CheckFailure.failed("语义不确定的 Dock 动画项不应再被排除")
        }
        guard case .toggle(let dockAnimationPreference) = dockAnimation.control else {
            throw CheckFailure.failed("Dock 动画实验必须使用可删除恢复的开关")
        }
        try require(
            dockAnimationPreference.readAddress == PreferenceAddress(
                domain: "com.apple.dock",
                key: "autohide-time-modifier"
            ) && dockAnimationPreference.enabledValue == .float(0.18),
            "Dock 动画实验必须保留浮点 0.18 预设"
        )
        try require(
            dockAnimation.caution == .compatibility && dockAnimation.stability.isUnstable,
            "Dock 动画实验缺少双重风险标记"
        )
        guard let dockAnimationParameter = dockAnimation.customization?.parameters.first,
              dockAnimation.customization?.parameters.count == 1 else {
            throw CheckFailure.failed("Dock 动画实验应提供一个受限自定义参数")
        }
        try require(
            dockAnimationParameter.address == dockAnimationPreference.readAddress,
            "Dock 动画滑块必须写入主开关读取的同一偏好地址"
        )
        try require(
            dockAnimationParameter.range == 0...2 &&
                dockAnimationParameter.step == 0.001 &&
                dockAnimationParameter.precision == 3,
            "Dock 动画系数范围必须为 0.000–2.000，步进必须为 0.001"
        )
        try require(
            dockAnimationParameter.presetValue == 0.18 &&
                dockAnimationParameter.normalized(dockAnimationParameter.presetValue) == 0.18,
            "Dock 动画滑块必须精确保留 0.18 安全预设"
        )
        try require(
            dockAnimationParameter.normalized(-1) == 0 &&
                dockAnimationParameter.normalized(3) == 2,
            "Dock 动画滑块未限制越界值"
        )
        try require(
            dockAnimationParameter.normalized(.nan) == 0.18 &&
                dockAnimationParameter.normalized(.infinity) == 0.18,
            "Dock 动画滑块必须把非有限值恢复为安全预设"
        )
        guard case .float(let storedDockAnimation) =
            dockAnimationParameter.preferenceValue(for: 0.35) else {
            throw CheckFailure.failed("Dock 动画系数必须写入浮点值")
        }
        try require(
            abs(storedDockAnimation - 0.35) < 0.0001,
            "Dock 动画滑块写入值不准确"
        )
        guard let dockAnimationNumeric = dockAnimation.numericConfiguration else {
            throw CheckFailure.failed("Dock 动画缺少统一数值读回契约")
        }
        let exactDockCurrent = dockAnimationNumeric.currentValues(using: [
            dockAnimationParameter.address: .float(0.05)
        ])
        try require(
            exactDockCurrent[dockAnimationParameter.id] == .value(0.05, rawValue: .float(0.05)) &&
                dockAnimationNumeric.loadableDrafts(from: exactDockCurrent)?[
                    dockAnimationParameter.id
                ] == 0.05 &&
                dockAnimationNumeric.expectedSnapshots(from: exactDockCurrent) == [
                    PreferenceSnapshot(
                        address: dockAnimationParameter.address,
                        value: .float(0.05)
                    )
                ],
            "合法系统当前值没有保持为独立的可载入精确值"
        )
        let missingDockCurrent = dockAnimationNumeric.currentValues(using: [:])
        try require(
            missingDockCurrent[dockAnimationParameter.id] == .notSet &&
                dockAnimationNumeric.loadableDrafts(from: missingDockCurrent) == nil &&
                dockAnimationNumeric.expectedSnapshots(from: missingDockCurrent) == [
                    PreferenceSnapshot(address: dockAnimationParameter.address, value: nil)
                ],
            "缺失键不能被安全预设冒充为系统当前值"
        )
        for invalidStoredValue in [
            PreferenceValue.integer(1),
            PreferenceValue.float(2.001),
            PreferenceValue.float(0.0505)
        ] {
            let invalidCurrent = dockAnimationNumeric.currentValues(using: [
                dockAnimationParameter.address: invalidStoredValue
            ])
            guard let invalidState = invalidCurrent[dockAnimationParameter.id],
                  case .invalid = invalidState else {
                throw CheckFailure.failed("类型、范围或分度错误的当前值仍可载入")
            }
            try require(
                dockAnimationNumeric.loadableDrafts(from: invalidCurrent) == nil &&
                    dockAnimationNumeric.expectedSnapshots(from: invalidCurrent) == nil,
                "非法系统当前值生成了草稿载入计划"
            )
        }

        let newlyIncludedUncertainIDs: Set<String> = [
            "dock.fastAnimation",
            "dock.dimHidden",
            "dock.singleApp",
            "dock.disableLegacyLaunchpadPinchGesture",
            "finder.quickLookTextSelection",
            "trackpad.legacyThreeFingerDoubleTap"
        ]
        try require(
            newlyIncludedUncertainIDs.isSubset(of: Set(items.map(\.id))),
            "此前因语义或效果不确定而排除的可逆候选未完整收录"
        )

        guard let legacyTrackpad = items.first(where: {
            $0.id == "trackpad.legacyThreeFingerDoubleTap"
        }), case .toggle(let legacyTrackpadPreference) = legacyTrackpad.control else {
            throw CheckFailure.failed("缺少遗留三指双击实验")
        }
        try require(
            Set(legacyTrackpadPreference.enableMutations.map(\.address.domain)) == Set([
                "com.apple.AppleMultitouchTrackpad",
                "com.apple.driver.AppleBluetoothMultitouch.trackpad"
            ]),
            "遗留三指双击实验必须同时覆盖内建与 Bluetooth 触控板域"
        )
        try require(
            legacyTrackpadPreference.enableMutations.allSatisfy {
                $0.value == .integer(2)
            } && legacyTrackpadPreference.disableMutations.allSatisfy {
                $0.value == nil
            },
            "遗留三指双击实验必须使用固定整数 2，并通过删除键恢复"
        )

        let customizableItems = items.filter { $0.numericConfiguration != nil }
        try require(
            customizableItems.count == 7 &&
                customizableItems.compactMap(\.numericConfiguration).flatMap(\.parameters).count == 10,
            "自定义选项应包含 7 组、10 个受控参数"
        )
        try require(
            Set(customizableItems.map(\.id)) == Set([
                "dock.instantReveal",
                "dock.fastAnimation",
                "dock.iconSizes",
                "keyboard.ultraFast",
                "windows.tooltipDelay",
                "system.compactMenuBar",
                "system.screensaverIdle"
            ]),
            "自定义选项目录不符合安全审计结果"
        )

        guard let repeatSpeed = items.first(where: { $0.id == "keyboard.ultraFast" }),
              case .numeric(let repeatPreference) = repeatSpeed.control else {
            throw CheckFailure.failed("按键重复速度必须迁移为一等数值控件")
        }
        try require(
            repeatSpeed.customization == nil && repeatPreference.parameters.count == 2,
            "一等数值控件不得再次藏在附属 customization 中"
        )
        try require(
            Set(repeatPreference.parameters.map(\.address.key)) ==
                Set(["KeyRepeat", "InitialKeyRepeat"]),
            "按键重复速度必须继续成组管理两个系统刻度"
        )
        let repeatCurrentValues = repeatPreference.currentValues(using: [
            repeatPreference.parameters[0].address: .integer(3),
            repeatPreference.parameters[1].address: .integer(15)
        ])
        try require(
            repeatPreference.loadableDrafts(from: repeatCurrentValues) == [
                repeatPreference.parameters[0].id: 3,
                repeatPreference.parameters[1].id: 15
            ],
            "双参数系统当前值没有成组生成草稿载入计划"
        )
        let partialRepeatCurrent = repeatPreference.currentValues(using: [
            repeatPreference.parameters[0].address: .integer(3)
        ])
        try require(
            repeatPreference.loadableDrafts(from: partialRepeatCurrent) == nil,
            "双参数当前值缺失一项时不得拼接旧草稿"
        )
        try require(
            repeatSpeed.source.exposure == .systemSettingsEnhancement &&
                repeatSpeed.source.enhancementKind == .exactValue,
            "按键重复速度缺少系统设置增强·精确值标签"
        )
        if case .restoreBaseline = repeatSpeed.recovery.strategy {
            // Expected.
        } else {
            throw CheckFailure.failed("按键重复速度必须恢复接管前值，不能盲删键")
        }

        guard let launchAnimation = items.first(where: { $0.id == "dock.noLaunchAnimation" }),
              case .toggle(let launchAnimationPreference) = launchAnimation.control else {
            throw CheckFailure.failed("缺少系统设置启动动画镜像")
        }
        try require(
            launchAnimationPreference.disableMutations.map(\.value) == [.bool(true)],
            "关闭启动动画镜像时必须显式写回 true，而不是删除后猜测默认值"
        )

        let advancedItems = items.filter { $0.category == .advanced }
        try require(
            Set(advancedItems.compactMap(\.privilegedKey)) == Set([
                "ttyskeepawake", "proximitywake", "acwake"
            ]),
            "高级分类的 pmset 白名单不符合预期"
        )
        try require(
            advancedItems.allSatisfy {
                $0.requiresAdministrator && !$0.supportsRecoveryAction &&
                    $0.caution == .privileged && $0.allAddresses.isEmpty
            },
            "高级功能必须隔离为独立管理员开关"
        )

        guard let dockDelay = items.first(where: { $0.id == "dock.instantReveal" })?
            .customization?.parameters.first else {
            throw CheckFailure.failed("缺少程序坞显示延迟自定义参数")
        }
        try require(dockDelay.range == 0...2, "程序坞显示延迟范围必须为 0–2 秒")
        try require(
            dockDelay.step == 0.001 && dockDelay.precision == 3,
            "程序坞显示延迟步进必须为 0.001 秒"
        )
        try require(dockDelay.normalized(-1) == 0, "程序坞延迟未限制负值")
        try require(dockDelay.normalized(3) == 2, "程序坞延迟未限制过大值")
        try require(dockDelay.normalized(.nan) == 0, "程序坞延迟未拒绝 NaN")
        try require(dockDelay.normalized(.infinity) == 0, "程序坞延迟未拒绝无穷大")
        guard case .float(let storedDockDelay) = dockDelay.preferenceValue(for: 0.35) else {
            throw CheckFailure.failed("程序坞延迟必须写入浮点秒数")
        }
        try require(
            abs(storedDockDelay - 0.35) < 0.0001,
            "程序坞延迟写入值不准确"
        )

        guard let tooltipDelay = items.first(where: { $0.id == "windows.tooltipDelay" })?
            .customization?.parameters.first else {
            throw CheckFailure.failed("缺少工具提示延迟自定义参数")
        }
        try require(
            tooltipDelay.step == 0.001 && tooltipDelay.precision == 3 &&
                tooltipDelay.preferenceValue(for: 0.351) == .integer(351),
            "工具提示延迟必须以 1 毫秒为最小分度并换算为整数毫秒"
        )

        guard let menuCustomization = menuBar?.customization else {
            throw CheckFailure.failed("缺少菜单栏间距自定义参数")
        }
        try require(menuCustomization.parameters.count == 2, "菜单栏应提供两项独立间距")
        try require(
            menuCustomization.parameters.allSatisfy {
                $0.range == 0...16 && $0.step == 1 && $0.address.hostScope == .currentHost
            },
            "菜单栏自定义必须限制为当前主机 0–16 点"
        )
        try require(
            menuCustomization.mutations(using: [
                "spacing": 6,
                "selectionPadding": 5
            ]).allSatisfy { $0.command.hasPrefix("defaults -currentHost write") },
            "菜单栏自定义命令必须保留 -currentHost"
        )
    }

    private static func checkPrecisionEnhancementModels() throws {
        guard let dock = PreferenceCatalog.items.first(where: { $0.id == "dock.iconSizes" }),
              let sizes = dock.numericConfiguration,
              let tile = sizes.parameters.first(where: { $0.id == "tileSize" }),
              let large = sizes.parameters.first(where: { $0.id == "largeSize" }),
              let saver = PreferenceCatalog.items.first(where: { $0.id == "system.screensaverIdle" }),
              let idle = saver.numericConfiguration,
              let seconds = idle.parameters.first else {
            throw CheckFailure.failed("1.8 精确控制目录不完整")
        }
        try require(sizes.initializesDraftsFromCurrentValue && idle.initializesDraftsFromCurrentValue,
                    "新增数值组必须优先使用有效当前值初始化草稿")
        try require(sizes.parameters.allSatisfy {
            $0.range == 16...128 && $0.step == 1 && $0.precision == 0 &&
                $0.preferenceValue(for: 35) == .float(35)
        }, "Dock 两种尺寸必须使用整点浮点值写入")
        try require(tile.presetValue == 48 && large.presetValue == 64,
                    "Dock 应用预设必须为 48 / 64")
        for raw in [PreferenceValue.integer(35), .float(35)] {
            let current = sizes.currentValues(using: [tile.address: raw, large.address: .float(37)])
            try require(current[tile.id] == .value(35, rawValue: raw), "Dock 读回未保留原始类型")
            try require(sizes.loadableDrafts(from: current) == [tile.id: 35, large.id: 37],
                        "Dock 合法整数或浮点值不可载入")
            try require(sizes.expectedSnapshots(from: current) == [
                PreferenceSnapshot(address: tile.address, value: raw),
                PreferenceSnapshot(address: large.address, value: .float(37))
            ], "Dock 冲突快照改写了原始数值类型")
        }
        for raw in [PreferenceValue.float(35.5), .integer(15), .float(129), .bool(true), .string("35")] {
            if case .invalid = tile.currentValue(from: raw) {} else {
                throw CheckFailure.failed("Dock 接受了不合法读回 \(raw.displayValue)")
            }
        }
        try require(sizes.validationError(using: [tile.id: 64, large.id: 48]) != nil &&
                    sizes.mutations(using: [tile.id: 64, large.id: 48]).isEmpty,
                    "放大尺寸小于普通尺寸时不得生成写入计划")
        try require(sizes.validationError(using: [tile.id: 48, large.id: 48]) == nil,
                    "相同普通和放大尺寸应当合法")
        try require(Set(dock.allAddresses.map(\.key)) == Set(["tilesize", "largesize"]) &&
                    Set(dock.contextAddresses.map(\.key)) == Set(["magnification", "size-immutable", "magsize-immutable"]) &&
                    Set(dock.lockingContextAddresses.map(\.key)) == Set(["size-immutable", "magsize-immutable"]),
                    "Dock 写入地址与只读上下文未正确隔离")
        try require(Set(dock.readAddresses) == Set(dock.allAddresses + dock.contextAddresses),
                    "Dock 读取地址遗漏只读上下文")
        try require(seconds.address == PreferenceAddress(domain: "com.apple.screensaver", key: "idleTime", hostScope: .currentHost) &&
                    seconds.range == 1...3600 && seconds.step == 1 && seconds.presetValue == 300,
                    "屏保必须使用 ByHost 秒数与 1–3600 范围")
        try require(seconds.specialValues.map(\.value) == [0] && seconds.displayValue(0) == "永不" &&
                    seconds.normalized(0) == 0 && seconds.preferenceValue(for: 0) == .integer(0),
                    "屏保 0 必须独立表示永不，不能归一化为 1")
        try require(seconds.presets.map(\.value) == [60, 300, 600, 1800, 3600],
                    "屏保预设不符合 1、5、10、30、60 分钟")
        let never = idle.currentValues(using: [seconds.address: .integer(0)])
        let missing = idle.currentValues(using: [:])
        try require(never[seconds.id] == .value(0, rawValue: .integer(0)) &&
                    missing[seconds.id] == .notSet && idle.loadableDrafts(from: never)?[seconds.id] == 0 &&
                    idle.loadableDrafts(from: missing) == nil,
                    "屏保永不与缺失键未区分")
        try require(idle.expectedSnapshots(from: never) == [PreferenceSnapshot(address: seconds.address, value: .integer(0))] &&
                    idle.expectedSnapshots(from: missing) == [PreferenceSnapshot(address: seconds.address, value: nil)],
                    "屏保快照未区分 0 与 nil")
        let ordinary = PreferenceAddress(domain: seconds.address.domain, key: seconds.address.key)
        try require(idle.currentValues(using: [ordinary: .integer(600)])[seconds.id] == .notSet,
                    "屏保误把普通域读回当成 ByHost 值")
        try require(idle.mutations(using: [seconds.id: 0]).first?.command.contains("-currentHost write") == true,
                    "屏保写入计划缺少 -currentHost")
        for raw in [PreferenceValue.float(0), .integer(-1), .integer(3601)] {
            if case .invalid = seconds.currentValue(from: raw) {} else {
                throw CheckFailure.failed("屏保接受了错误类型或范围的当前值")
            }
        }
        for item in [dock, saver] {
            try require(item.source.exposure == .systemSettingsEnhancement &&
                        item.source.enhancementKind == .exactValue && item.stability.isUnstable &&
                        item.caution == .compatibility,
                        "新增精确控制缺少来源或实验性注释")
            guard case .restoreBaseline = item.recovery.strategy else {
                throw CheckFailure.failed("新增精确控制必须恢复接管前值")
            }
        }
    }

    private static func checkRecoveryPlanningContracts() throws {
        let first = PreferenceAddress(domain: "com.codex.contract", key: "First")
        let second = PreferenceAddress(domain: "com.codex.contract", key: "Second")
        let numeric = NumericPreference(
            detail: "纯恢复规划测试",
            parameters: [
                NumericPreferenceParameter(
                    id: "first",
                    title: "第一项",
                    detail: "测试",
                    address: first,
                    range: 0...100,
                    step: 1,
                    presetValue: 1,
                    storage: .integer,
                    unit: "",
                    precision: 0
                ),
                NumericPreferenceParameter(
                    id: "second",
                    title: "第二项",
                    detail: "测试",
                    address: second,
                    range: 0...100,
                    step: 1,
                    presetValue: 10,
                    storage: .integer,
                    unit: "",
                    precision: 0
                )
            ]
        )
        let item = PreferenceItem(
            id: "contract.numeric",
            category: .keyboard,
            title: "恢复规划测试",
            detail: "测试",
            symbol: "number",
            control: .numeric(numeric),
            restartProcesses: [],
            effectHint: "测试",
            caution: .none,
            source: PreferenceSource(
                exposure: .systemSettingsEnhancement,
                enhancementKind: .exactValue,
                systemSettings: nil,
                note: nil
            ),
            recovery: .restoreBaseline
        )
        let baseline = PreferenceRecoveryBaseline(
            itemID: item.id,
            before: [
                PreferenceSnapshot(address: first, value: .integer(48)),
                PreferenceSnapshot(address: second, value: nil)
            ],
            lastApplied: [
                PreferenceSnapshot(address: first, value: .integer(1)),
                PreferenceSnapshot(address: second, value: .integer(10))
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        guard let plan = item.recoveryPlan(baseline: baseline) else {
            throw CheckFailure.failed("完整接管前快照没有生成恢复计划")
        }
        let restored = Dictionary(uniqueKeysWithValues: plan.mutations.map {
            ($0.address, $0.value)
        })
        try require(plan.mutations.count == 2, "恢复计划必须包含原本缺失的键")
        try require(restored[first] == .integer(48), "恢复计划没有保留整数原值")
        try require(
            plan.mutations.contains { $0.address == second && $0.value == nil },
            "恢复计划没有保留键原本不存在的状态"
        )
        try require(plan.expectedCurrent == baseline.lastApplied, "恢复计划缺少外部冲突基准")
        try require(plan.clearsBaseline, "恢复接管前值后必须清除当前接管记录")
        try require(
            item.recoveryPlan(baseline: nil) == nil,
            "缺少接管前快照时不得退化为删除键"
        )

        let deleteItem = PreferenceItem(
            id: "contract.delete",
            category: .dock,
            title: "删除规划测试",
            detail: "测试",
            symbol: "trash",
            control: .text(TextPreference(address: first, placeholder: "")),
            restartProcesses: [],
            effectHint: "测试",
            caution: .none
        )
        let deletePlan = deleteItem.recoveryPlan(baseline: nil)
        try require(
            deletePlan?.mutations.count == 1 && deletePlan?.mutations.first?.value == nil,
            "只有声明 deleteExplicit 的项目才应生成删除计划"
        )

        let fine = NumericPreferenceParameter(
            id: "fine",
            title: "精确值",
            detail: "测试",
            address: first,
            range: 0...1,
            step: 0.001,
            presetValue: 0,
            storage: .float,
            unit: "",
            precision: 3
        )
        try require(fine.preferenceValue(for: 0) == .float(0), "显式 0 不得转换为删除")
        try require(fine.exactInputError(for: 0.001) == nil, "合法最小分度被拒绝")
        try require(fine.exactInputError(for: 0.0005) != nil, "未对齐最小分度的输入未被拒绝")
        try require(fine.exactInputError(for: .nan) != nil, "精确输入未拒绝 NaN")
        try require(PreferenceManagementState.forced([first]).isReadOnly, "受管理项必须只读")
        try require(!PreferenceManagementState.unmanaged.isReadOnly, "未受管理项不应被禁用")
        try require(
            numeric.parameters[0].displayedValue(from: .integer(101)) == nil &&
                numeric.parameters[0].displayedValue(from: .float(10)) == nil,
            "越界或错误标量类型的系统现值不得被夹限后伪装成安全值"
        )

        let malformedBaseline = PreferenceRecoveryBaseline(
            itemID: item.id,
            before: baseline.before + [baseline.before[0]],
            lastApplied: baseline.lastApplied,
            createdAt: baseline.createdAt
        )
        try require(
            item.recoveryPlan(baseline: malformedBaseline) == nil,
            "包含重复地址的接管前快照必须被拒绝"
        )
        let wrongItemBaseline = PreferenceRecoveryBaseline(
            itemID: "contract.other",
            before: baseline.before,
            lastApplied: baseline.lastApplied,
            createdAt: baseline.createdAt
        )
        try require(
            item.recoveryPlan(baseline: wrongItemBaseline) == nil,
            "其他功能项的接管前快照不得被复用"
        )
        let explicitZeroBaseline = PreferenceRecoveryBaseline(
            itemID: item.id,
            before: [
                PreferenceSnapshot(address: first, value: .integer(0)),
                PreferenceSnapshot(address: second, value: .float(0))
            ],
            lastApplied: baseline.lastApplied,
            createdAt: baseline.createdAt
        )
        let zeroPlan = item.recoveryPlan(baseline: explicitZeroBaseline)
        try require(
            zeroPlan?.mutations.contains {
                $0.address == first && $0.value == .integer(0)
            } == true && zeroPlan?.mutations.contains {
                $0.address == second && $0.value == .float(0)
            } == true,
            "显式整数 0、浮点 0 与缺失 nil 必须保持不同恢复语义"
        )

        let invalidPresetItem = PreferenceItem(
            id: "contract.invalidPreset",
            category: .keyboard,
            title: "错误预设规划测试",
            detail: "测试",
            symbol: "number",
            control: .numeric(numeric),
            restartProcesses: [],
            effectHint: "测试",
            caution: .none,
            recovery: PreferenceRecovery(
                strategy: .writePreset([
                    PreferenceMutation(address: first, value: .integer(1))
                ]),
                actionTitle: "写入预设",
                detail: "测试"
            )
        )
        try require(
            invalidPresetItem.recoveryPlan(baseline: nil) == nil,
            "不完整的 writePreset 恢复计划必须被拒绝"
        )
    }

    @MainActor
    private static func checkRecordingCustomizationContracts() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "TerminalSettingsRecordingChecks-\(UUID().uuidString)",
                isDirectory: true
            )
        let undoStorageURL = directory.appendingPathComponent("last-undo.json")
        let pendingTransactionURL = directory
            .appendingPathComponent("pending-preference-transaction.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        guard let item = PreferenceCatalog.items.first(where: {
            $0.id == "dock.fastAnimation"
        }), let parameter = item.customization?.parameters.first else {
            throw CheckFailure.failed("缺少目录内 Dock 动画自定义项")
        }
        let address = parameter.address

        let log = RecordingDependencyLog()
        let executor = RecordingPreferenceExecutor(
            values: [address: .float(0.05)],
            allowedMutations: [(address, .float(0.181))],
            log: log
        )
        let store = PreferencesStore(
            executor: executor,
            restarter: RecordingRestarter(log: log),
            managementProvider: RecordingManagementProvider(log: log),
            powerExecutor: FailClosedPowerExecutor(log: log),
            journal: RecordingJournal(expectedURL: pendingTransactionURL, log: log),
            appState: InMemoryApplicationState(),
            timeProvider: FixedTimeProvider(),
            identifierProvider: FixedIdentifierProvider(),
            undoStorageURL: undoStorageURL
        )
        store.prepareCustomizationModeTest(
            item,
            parentEnabled: true,
            currentValues: [address: .float(0.05)]
        )

        var checkpoint = log.checkpoint()
        store.setCustomizationEnabled(item, enabled: true)
        try require(store.isCustomizationEnabled(item), "纯内存测试未开启自定义编辑")
        try requireNoRecordedExternalEffects(
            log.events(since: checkpoint),
            context: "setCustomizationEnabled"
        )

        checkpoint = log.checkpoint()
        store.setCustomizationDraft(item, parameter: parameter, value: 0.181)
        try require(
            store.customizationDraft(for: item, parameter: parameter) == 0.181,
            "纯内存测试未更新自定义草稿"
        )
        try requireNoRecordedExternalEffects(
            log.events(since: checkpoint),
            context: "setCustomizationDraft"
        )

        checkpoint = log.checkpoint()
        store.setCustomizationInputError(
            item,
            parameter: parameter,
            message: "精确输入尚未有效提交"
        )
        try require(!store.canApplyCustomization(item), "输入错误未阻止 Apply")
        try requireNoRecordedExternalEffects(
            log.events(since: checkpoint),
            context: "setCustomizationInputError"
        )

        checkpoint = log.checkpoint()
        store.applyCustomization(item)
        try require(
            !store.isWorking && !store.canUndo && !store.hasPendingPreferenceTransaction,
            "输入错误下的 Apply 不应启动事务或创建撤销状态"
        )
        try requireNoRecordedExternalEffects(
            log.events(since: checkpoint),
            context: "输入错误下的 applyCustomization"
        )

        checkpoint = log.checkpoint()
        store.setCustomizationInputError(item, parameter: parameter, message: nil)
        try requireNoRecordedExternalEffects(
            log.events(since: checkpoint),
            context: "清除自定义输入错误"
        )

        checkpoint = log.checkpoint()
        store.loadCurrentCustomizationValues(item)
        try require(
            store.customizationDraft(for: item, parameter: parameter) == 0.05 &&
                store.customizationLoadRevision(for: item) == 1,
            "loadCurrent 未将最近读取值复制到草稿"
        )
        try require(
            store.customizationCurrentValue(for: item, parameter: parameter) == .value(0.05, rawValue: .float(0.05)),
            "loadCurrent 意外改变了独立保存的系统当前值"
        )
        try requireNoRecordedExternalEffects(
            log.events(since: checkpoint),
            context: "loadCurrentCustomizationValues"
        )

        checkpoint = log.checkpoint()
        store.setCustomizationDraft(item, parameter: parameter, value: 0.181)
        try requireNoRecordedExternalEffects(
            log.events(since: checkpoint),
            context: "显式 Apply 前的草稿编辑"
        )
        try require(store.canApplyCustomization(item), "合法草稿未开放显式 Apply")

        let applyCheckpoint = log.checkpoint()
        store.applyCustomization(item)
        try waitUntil("纯内存自定义 Apply 未完成") {
            !store.isWorking
        }
        let applyEvents = log.events(since: applyCheckpoint)

        let mutationIndices = applyEvents.indices.filter { index in
            if case .preferenceApply = applyEvents[index] { return true }
            return false
        }
        try require(mutationIndices.count == 1, "显式 Apply 必须且只能产生一笔 mutation")
        guard let mutationIndex = mutationIndices.first,
              case .preferenceApply(let appliedAddress, let appliedValue) =
                applyEvents[mutationIndex] else {
            throw CheckFailure.failed("显式 Apply 缺少可审计的 mutation")
        }
        try require(
            appliedAddress == address && appliedValue == .float(0.181),
            "显式 Apply 的地址或数值不精确"
        )

        let journalPersistIndices = applyEvents.indices.filter { index in
            if case .journalPersist = applyEvents[index] { return true }
            return false
        }
        guard let firstPersistIndex = journalPersistIndices.first,
              case .journalPersist(let persistedURL, let before, let after) =
                applyEvents[firstPersistIndex] else {
            throw CheckFailure.failed("显式 Apply 未创建写前 journal")
        }
        try require(
            firstPersistIndex < mutationIndex,
            "写前 journal 必须先于首笔 preference mutation"
        )
        try require(
            persistedURL == pendingTransactionURL &&
                before == [PreferenceSnapshot(address: address, value: .float(0.05))] &&
                after == [PreferenceSnapshot(address: address, value: .float(0.181))],
            "写前 journal 未精确记录 mutation 前后状态"
        )

        let restartEvents = applyEvents.compactMap { event -> [String]? in
            if case .restart(let processNames) = event { return processNames }
            return nil
        }
        try require(
            restartEvents == [["Dock"]],
            "显式 Apply 必须精确重启 Dock 一次"
        )
        try require(
            !applyEvents.contains(where: { event in
                switch event {
                case .preferenceRestore, .preferenceRestorePreservingExternalChanges,
                        .powerAuthorization, .powerApply, .powerRestore,
                        .powerRestorePreservingExternalChanges:
                    return true
                default:
                    return false
                }
            }),
            "普通显式 Apply 不得触发 restore 或任何电源授权/写入"
        )
        let journalRemoveIndices = applyEvents.indices.filter { index in
            if case .journalRemove = applyEvents[index] { return true }
            return false
        }
        try require(
            journalRemoveIndices.count == 1 &&
                journalRemoveIndices[0] > mutationIndex,
            "成功事务必须在 mutation 完成后清理一次 journal"
        )
        try require(
            executor.value(for: address) == .float(0.181),
            "内存偏好最终值与显式草稿不一致"
        )
        try require(
            !store.hasPendingPreferenceTransaction && store.canUndo,
            "成功 Apply 后必须 pending=false 且 canUndo=true"
        )
        try require(
            FileManager.default.fileExists(atPath: undoStorageURL.path),
            "成功 Apply 未在隔离的临时 URL 持久化撤销记录"
        )

        let conflictDirectory = directory.appendingPathComponent(
            "expected-current-conflict",
            isDirectory: true
        )
        let conflictUndoURL = conflictDirectory.appendingPathComponent("last-undo.json")
        let conflictPendingURL = conflictDirectory
            .appendingPathComponent("pending-preference-transaction.json")
        let conflictLog = RecordingDependencyLog()
        let conflictExecutor = RecordingPreferenceExecutor(
            values: [address: .float(0.06)],
            allowedMutations: [],
            log: conflictLog
        )
        let conflictStore = PreferencesStore(
            executor: conflictExecutor,
            restarter: RecordingRestarter(log: conflictLog),
            managementProvider: RecordingManagementProvider(log: conflictLog),
            powerExecutor: FailClosedPowerExecutor(log: conflictLog),
            journal: RecordingJournal(expectedURL: conflictPendingURL, log: conflictLog),
            appState: InMemoryApplicationState(),
            timeProvider: FixedTimeProvider(),
            identifierProvider: FixedIdentifierProvider(),
            undoStorageURL: conflictUndoURL
        )
        conflictStore.prepareCustomizationModeTest(
            item,
            parentEnabled: true,
            currentValues: [address: .float(0.05)]
        )
        conflictStore.setCustomizationEnabled(item, enabled: true)
        conflictStore.setCustomizationDraft(item, parameter: parameter, value: 0.181)
        try require(
            conflictStore.canApplyCustomization(item),
            "外部冲突测试未进入可执行 expectedCurrent 预检的状态"
        )

        let conflictCheckpoint = conflictLog.checkpoint()
        conflictStore.applyCustomization(item)
        try waitUntil("expectedCurrent 外部冲突预检未完成") {
            !conflictStore.isWorking
        }
        let conflictEvents = conflictLog.events(since: conflictCheckpoint)
        let ensureUnchangedCount = conflictEvents.filter { event in
            if case .preferenceEnsureUnchanged = event { return true }
            return false
        }.count
        let conflictPersistCount = conflictEvents.filter { event in
            if case .journalPersist = event { return true }
            return false
        }.count
        let conflictApplyCount = conflictEvents.filter { event in
            if case .preferenceApply = event { return true }
            return false
        }.count
        let conflictRestartCount = conflictEvents.filter { event in
            if case .restart = event { return true }
            return false
        }.count
        try require(
            ensureUnchangedCount == 1,
            "expectedCurrent 外部冲突路径没有执行一次完整预检"
        )
        try require(
            conflictPersistCount == 0 && conflictApplyCount == 0 &&
                conflictRestartCount == 0,
            "外部冲突必须在 journal、首笔 mutation 与进程重启之前中止"
        )
        try require(
            conflictExecutor.value(for: address) == .float(0.06),
            "expectedCurrent 冲突覆盖了外部较新值"
        )
        try require(
            conflictStore.alert?.message.contains("外部冲突") == true &&
                !conflictStore.hasPendingPreferenceTransaction && !conflictStore.canUndo,
            "expectedCurrent 冲突未以无 pending、无 undo 的失败状态结束"
        )
        try require(
            !FileManager.default.fileExists(atPath: conflictUndoURL.path),
            "预检冲突不应创建撤销文件"
        )
    }

    @MainActor
    private static func checkRecordingPrecisionEnhancements() throws {
        guard let dock = PreferenceCatalog.items.first(where: { $0.id == "dock.iconSizes" }),
              let sizes = dock.numericConfiguration,
              let tile = sizes.parameters.first(where: { $0.id == "tileSize" }),
              let large = sizes.parameters.first(where: { $0.id == "largeSize" }),
              let saver = PreferenceCatalog.items.first(where: { $0.id == "system.screensaverIdle" }),
              let seconds = saver.numericConfiguration?.parameters.first else {
            throw CheckFailure.failed("缺少 1.8 录制测试目录")
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TerminalSettingsPrecisionRecording-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func fixture(
            _ name: String,
            values: [PreferenceAddress: PreferenceValue],
            mutations: [(PreferenceAddress, PreferenceValue?)] = [],
            restores: [PreferenceSnapshot] = [],
            failure: PreferenceAddress? = nil,
            appState: InMemoryApplicationState = InMemoryApplicationState(),
            forced: Set<PreferenceAddress> = [],
            managementFails: Bool = false
        ) -> (PreferencesStore, RecordingPreferenceExecutor, RecordingDependencyLog) {
            let path = directory.appendingPathComponent(name, isDirectory: true)
            let log = RecordingDependencyLog()
            let executor = RecordingPreferenceExecutor(values: values, allowedMutations: mutations,
                allowedRestores: restores, failingApplyAddress: failure, log: log)
            let store = PreferencesStore(
                executor: executor, restarter: RecordingRestarter(log: log),
                managementProvider: RecordingManagementProvider(log: log, forced: forced, shouldFail: managementFails),
                powerExecutor: FailClosedPowerExecutor(log: log),
                journal: RecordingJournal(expectedURL: path.appendingPathComponent("pending-preference-transaction.json"), log: log),
                appState: appState, timeProvider: FixedTimeProvider(), identifierProvider: FixedIdentifierProvider(),
                undoStorageURL: path.appendingPathComponent("last-undo.json")
            )
            return (store, executor, log)
        }

        let magnification = PreferenceAddress(domain: "com.apple.dock", key: "magnification")
        for (index, raw) in [PreferenceValue.integer(35), .float(35)].enumerated() {
            let initial: [PreferenceAddress: PreferenceValue] = [tile.address: raw, large.address: .float(37), magnification: .bool(false)]
            let before = [PreferenceSnapshot(address: tile.address, value: raw),
                          PreferenceSnapshot(address: large.address, value: .float(37))]
            let (store, executor, log) = fixture("dock-type-\(index)", values: initial,
                mutations: [(tile.address, .float(40)), (large.address, .float(50))], restores: before)
            store.prepareCustomizationModeTest(dock, parentEnabled: true, currentValues: initial)
            try require(store.customizationDraft(for: dock, parameter: tile) == 35 &&
                        store.customizationDraft(for: dock, parameter: large) == 37,
                        "Dock 初始草稿没有采用有效当前值")
            let draftCheckpoint = log.checkpoint()
            store.setCustomizationEnabled(dock, enabled: true)
            store.setCustomizationDraft(dock, parameter: tile, value: 64)
            store.setCustomizationDraft(dock, parameter: large, value: 48)
            try require(!store.canApplyCustomization(dock) && store.customizationValidationError(dock) != nil,
                        "Dock 关系约束没有阻止 Apply")
            try require(store.previewCommands(for: dock).first { $0.0 == "自定义（当前数值）" }?.1.isEmpty == true,
                        "非法 Dock 组仍在命令预览中提供可写命令")
            store.applyCustomization(dock)
            try requireNoRecordedExternalEffects(log.events(since: draftCheckpoint), context: "Dock 非法尺寸组草稿")
            store.setCustomizationDraft(dock, parameter: tile, value: 40)
            store.setCustomizationDraft(dock, parameter: large, value: 50)
            try require(store.canApplyCustomization(dock), "关闭放大功能时应仍允许预存尺寸")
            let checkpoint = log.checkpoint()
            store.applyCustomization(dock)
            try waitUntil("Dock 双尺寸录制 Apply 未完成") { !store.isWorking }
            let events = log.events(since: checkpoint)
            let applied = events.compactMap { event -> PreferenceAddress? in
                if case .preferenceApply(let address, _) = event { return address }
                return nil
            }
            try require(applied == [tile.address, large.address] &&
                        executor.value(for: tile.address) == .float(40) &&
                        executor.value(for: large.address) == .float(50) && store.canUndo,
                        "Dock 两键未成组写入，或原类型造成假冲突")
            try require(events.compactMap { event -> [String]? in
                if case .restart(let names) = event { return names }
                return nil
            } == [["Dock"]], "Dock 两键成功后必须只重启一次")
            try require(events.contains { event in
                if case .journalPersist(_, let recordedBefore, _) = event {
                    return recordedBefore == before
                }
                return false
            }, "Dock WAL 没有保留读回原始类型")
            store.undo()
            try waitUntil("Dock 原类型撤销未完成") { !store.isWorking }
            try require(executor.value(for: tile.address) == raw &&
                        executor.value(for: large.address) == .float(37) && !store.canUndo &&
                        !store.hasPendingPreferenceTransaction,
                        "Dock 撤销未精确恢复原类型和值")
            try require(executor.value(for: magnification) == .bool(false), "Dock 意外写入放大功能开关")
            try require(!log.events(since: 0).contains { event in
                switch event {
                case .preferenceApply(let address, _): return dock.contextAddresses.contains(address)
                case .journalPersist(_, let before, let after):
                    return (before + after).contains { dock.contextAddresses.contains($0.address) }
                case .preferenceRestore(let snapshots):
                    return snapshots.contains { dock.contextAddresses.contains($0.address) }
                default: return false
                }
            }, "只读 Dock 上下文进入了写入、撤销或 WAL")
        }

        let original: [PreferenceAddress: PreferenceValue] = [tile.address: .float(35), large.address: .integer(37)]
        let originalSnapshots = [PreferenceSnapshot(address: tile.address, value: .float(35)),
                                 PreferenceSnapshot(address: large.address, value: .integer(37))]
        let (failedStore, failedExecutor, failedLog) = fixture("dock-second-write-failure", values: original,
            mutations: [(tile.address, .float(40)), (large.address, .float(50))],
            restores: originalSnapshots, failure: large.address)
        failedStore.prepareCustomizationModeTest(dock, parentEnabled: true, currentValues: original)
        failedStore.setCustomizationEnabled(dock, enabled: true)
        failedStore.setCustomizationDraft(dock, parameter: tile, value: 40)
        failedStore.setCustomizationDraft(dock, parameter: large, value: 50)
        failedStore.applyCustomization(dock)
        try waitUntil("Dock 第二键失败回滚未完成") { !failedStore.isWorking }
        try require(failedExecutor.value(for: tile.address) == .float(35) &&
                    failedExecutor.value(for: large.address) == .integer(37) &&
                    !failedStore.hasPendingPreferenceTransaction && !failedStore.canUndo,
                    "Dock 第二键失败后没有成组恢复原始类型")
        try require(failedLog.events(since: 0).contains { event in
            if case .preferenceRestore(let snapshots) = event { return snapshots == originalSnapshots }
            return false
        } && failedLog.events(since: 0).contains { event in
            if case .preferenceEnsureCurrentMatchesAny = event { return true }
            return false
        }, "Dock 第二键失败未先检查外部冲突再恢复原值")

        for lockAddress in dock.lockingContextAddresses {
            var lockedValues = original
            lockedValues[lockAddress] = .bool(true)
            let (lockedStore, _, lockedLog) = fixture("lock-\(lockAddress.key)", values: lockedValues)
            lockedStore.prepareCustomizationModeTest(dock, parentEnabled: true, currentValues: lockedValues)
            let checkpoint = lockedLog.checkpoint()
            try require(!lockedStore.canModify(dock), "Dock 锁定上下文生效后仍可修改")
            lockedStore.setCustomizationEnabled(dock, enabled: true)
            lockedStore.applyCustomization(dock)
            try requireNoRecordedExternalEffects(lockedLog.events(since: checkpoint), context: "Dock 锁定上下文")
        }
        for managedAddress in [tile.address, large.address] {
            let (managedStore, _, managedLog) = fixture("managed-\(managedAddress.key)", values: original, forced: [managedAddress])
            managedStore.refreshAll()
            try waitUntil("Dock 受管理测试刷新未完成") { !managedStore.isWorking }
            try require(!managedStore.canModify(dock), "任一尺寸受管理时整个尺寸组必须只读")
            try requireNoRecordedExternalEffects(managedLog.events(since: 0), context: "Dock 受管理读取")
        }
        for forcedLock in dock.lockingContextAddresses {
            let (forcedLockStore, _, forcedLockLog) = fixture("forced-lock-\(forcedLock.key)",
                values: original, forced: [forcedLock])
            forcedLockStore.refreshAll()
            try waitUntil("Dock 强制锁定键缺失导出测试未完成") { !forcedLockStore.isWorking }
            try require(!forcedLockStore.canModify(dock),
                        "锁定键虽未导出但被强制管理时，整个 Dock 尺寸组必须只读")
            try requireNoRecordedExternalEffects(forcedLockLog.events(since: 0), context: "Dock 强制锁定键读取")
        }
        let externalLock = dock.lockingContextAddresses[0]
        var changedContext = original
        changedContext[externalLock] = .bool(true)
        let (changedStore, _, changedLog) = fixture("lock-changed-before-apply", values: changedContext)
        changedStore.prepareCustomizationModeTest(dock, parentEnabled: true, currentValues: original)
        changedStore.setCustomizationEnabled(dock, enabled: true)
        changedStore.setCustomizationDraft(dock, parameter: tile, value: 40)
        changedStore.setCustomizationDraft(dock, parameter: large, value: 50)
        let changedCheckpoint = changedLog.checkpoint()
        changedStore.applyCustomization(dock)
        try waitUntil("Dock 应用前上下文复核未完成") { !changedStore.isWorking }
        try requireNoRecordedExternalEffects(changedLog.events(since: changedCheckpoint).filter {
            if case .journalRemove = $0 { return false }; return true
        }, context: "应用前新增 Dock 锁定")
        for forcedAddress in [large.address] + dock.lockingContextAddresses {
            let (newlyManaged, _, newlyManagedLog) = fixture("managed-before-apply-\(forcedAddress.key)", values: original, forced: [forcedAddress])
            newlyManaged.prepareCustomizationModeTest(dock, parentEnabled: true, currentValues: original)
            newlyManaged.setCustomizationEnabled(dock, enabled: true)
            newlyManaged.setCustomizationDraft(dock, parameter: tile, value: 40)
            newlyManaged.setCustomizationDraft(dock, parameter: large, value: 50)
            let managedCheckpoint = newlyManagedLog.checkpoint()
            newlyManaged.applyCustomization(dock)
            try waitUntil("Dock 应用前管理状态复核未完成") { !newlyManaged.isWorking }
            try requireNoRecordedExternalEffects(newlyManagedLog.events(since: managedCheckpoint).filter {
                if case .journalRemove = $0 { return false }; return true
            }, context: "应用前新增管理策略")
        }
        let (unknownStore, _, unknownLog) = fixture("management-unknown", values: original, managementFails: true)
        unknownStore.refreshAll()
        try waitUntil("管理状态失败测试刷新未完成") { !unknownStore.isWorking }
        try require(!unknownStore.canModify(dock) && !unknownStore.canModify(saver), "管理状态无法确认时必须只读")
        try requireNoRecordedExternalEffects(unknownLog.events(since: 0), context: "管理状态未知读取")

        let saverState = InMemoryApplicationState()
        let (missingStore, _, _) = fixture("missing-current-presets", values: [:])
        missingStore.prepareCustomizationModeTest(dock, parentEnabled: true)
        missingStore.prepareCustomizationModeTest(saver, parentEnabled: true)
        try require(missingStore.customizationDraft(for: dock, parameter: tile) == 48 &&
                    missingStore.customizationDraft(for: dock, parameter: large) == 64 &&
                    missingStore.customizationDraft(for: saver, parameter: seconds) == 300 &&
                    missingStore.customizationCurrentValue(for: saver, parameter: seconds) == .notSet,
                    "缺失当前值必须使用明确应用预设，不能伪装为系统当前值")
        let ordinaryIdle = PreferenceAddress(domain: seconds.address.domain, key: seconds.address.key)
        let saverInitial: [PreferenceAddress: PreferenceValue] = [seconds.address: .integer(0), ordinaryIdle: .integer(600)]
        let (saverStore, saverExecutor, saverLog) = fixture("saver", values: saverInitial,
            mutations: [(seconds.address, .integer(61))], appState: saverState)
        saverStore.prepareCustomizationModeTest(saver, parentEnabled: true, currentValues: saverInitial)
        try require(saverStore.customizationDraft(for: saver, parameter: seconds) == 0,
                    "屏保 0 当前值未用于初始化草稿")
        let saverCheckpoint = saverLog.checkpoint()
        saverStore.setCustomizationEnabled(saver, enabled: true)
        saverStore.setCustomizationSpecialValue(saver, parameter: seconds, value: nil)
        try require(saverStore.customizationDraft(for: saver, parameter: seconds) == 300,
                    "首次从永不切回计时必须恢复 5 分钟")
        for preset in seconds.presets {
            saverStore.applyCustomizationDraftPreset(saver, parameter: seconds, value: preset.value)
            try require(saverStore.customizationDraft(for: saver, parameter: seconds) == preset.value,
                        "屏保预设未只更新对应草稿")
        }
        saverStore.setCustomizationDraft(saver, parameter: seconds, value: 61)
        saverStore.setCustomizationSpecialValue(saver, parameter: seconds, value: 0)
        saverStore.setCustomizationEnabled(saver, enabled: false)
        saverStore.setCustomizationEnabled(saver, enabled: true)
        try require(saverStore.customizationDraft(for: saver, parameter: seconds) == 0 &&
                    saverStore.lastFiniteCustomizationDraft(for: saver, parameter: seconds) == 61,
                    "屏保永不草稿丢失或覆盖有限草稿")
        saverStore.loadCurrentCustomizationValues(saver)
        try require(saverStore.customizationDraft(for: saver, parameter: seconds) == 0,
                    "载入屏保当前值未保留永不")
        try requireNoRecordedExternalEffects(saverLog.events(since: saverCheckpoint), context: "屏保模式、预设、永不和载入草稿")
        let (reloadedSaver, _, reloadedLog) = fixture("saver-reload", values: saverInitial, appState: saverState)
        reloadedSaver.prepareCustomizationModeTest(saver, parentEnabled: true, currentValues: saverInitial)
        try require(reloadedSaver.customizationDraft(for: saver, parameter: seconds) == 0 &&
                    reloadedSaver.lastFiniteCustomizationDraft(for: saver, parameter: seconds) == 61,
                    "屏保特殊值和有限草稿未跨启动独立保存")
        reloadedSaver.setCustomizationSpecialValue(saver, parameter: seconds, value: nil)
        try require(reloadedSaver.customizationDraft(for: saver, parameter: seconds) == 61,
                    "重启后切回计时未恢复上次有限草稿")
        try requireNoRecordedExternalEffects(reloadedLog.events(since: 0), context: "屏保有限草稿重载")
        saverStore.setCustomizationSpecialValue(saver, parameter: seconds, value: nil)
        saverStore.applyCustomization(saver)
        try waitUntil("屏保 ByHost 录制 Apply 未完成") { !saverStore.isWorking }
        try require(saverExecutor.value(for: seconds.address) == .integer(61) &&
                    saverExecutor.value(for: ordinaryIdle) == .integer(600) &&
                    saverStore.canUndo && !saverStore.hasPendingPreferenceTransaction,
                    "屏保 Apply 未隔离 ByHost 与普通域")
        let saverWrites = saverLog.events(since: saverCheckpoint).compactMap { event -> PreferenceAddress? in
            if case .preferenceApply(let address, _) = event { return address }
            return nil
        }
        try require(saverWrites == [seconds.address], "屏保只应写入一次 ByHost idleTime")
    }

    @MainActor
    private static func checkPrivilegedTimeoutRetainsJournal(language: AppLanguage) throws {
        guard let item = PreferenceCatalog.items.first(where: { $0.privilegedKey == "ttyskeepawake" }) else {
            throw CheckFailure.failed("缺少管理员超时测试项目")
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TerminalSettingsPowerTimeout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = RecordingDependencyLog()
        let pendingURL = directory.appendingPathComponent("pending-preference-transaction.json")
        let journal = RecordingJournal(expectedURL: pendingURL, log: log)
        let state = InMemoryApplicationState()
        state.set(language.rawValue, forKey: AppLanguageStore.preferenceKey)
        let store = PreferencesStore(
            executor: RecordingPreferenceExecutor(values: [:], allowedMutations: [], log: log),
            restarter: RecordingRestarter(log: log), managementProvider: RecordingManagementProvider(log: log),
            powerExecutor: TimedOutPowerExecutor(log: log), journal: journal,
            appState: state, timeProvider: FixedTimeProvider(), identifierProvider: FixedIdentifierProvider(),
            undoStorageURL: directory.appendingPathComponent("last-undo.json")
        )
        store.prepareCustomizationModeTest(item, parentEnabled: true)
        let checkpoint = log.checkpoint()
        store.setToggle(item, enabled: false)
        try waitUntil("管理员 helper 超时替身测试未结束") { !store.isWorking }
        let events = log.events(since: checkpoint)
        try require(events.filter { if case .powerApply = $0 { return true }; return false }.count == 1 &&
                    events.filter { if case .powerRestorePreservingExternalChanges = $0 { return true }; return false }.count == 1 &&
                    events.filter { if case .powerVerify = $0 { return true }; return false }.count == 1,
                    "超时路径必须尝试并验证补偿")
        try require(store.hasPendingPreferenceTransaction &&
                    PreferenceCatalog.items.allSatisfy { !store.canModify($0) } &&
                    store.alert?.message.contains("helper") == true,
                    "补偿成功但 helper 状态未知时必须保留 WAL 并锁定写入")
        let retainedRecord = try journal.read(from: pendingURL)
        let resources = try localizationTestResources()
        let rendered = store.alert!.message.rendered(language: language, resources: resources)
        try require(rendered.contains(language == .english ? "recovery journal" : "恢复日志"),
                    "管理员超时错误没有按所选语言显示")
        try require(retainedRecord?.powerBefore?.first?.key == "ttyskeepawake" &&
                    !events.contains { if case .journalRemove = $0 { return true }; return false },
                    "helper 超时路径删除了需要保留的恢复日志")
        try require(!events.contains { event in
            switch event {
            case .preferenceApply, .preferenceRestore, .preferenceRestorePreservingExternalChanges, .restart: return true
            default: return false
            }
        }, "管理员超时替身不应产生普通偏好或进程重启")
    }

    @MainActor
    private static func checkUnreadableJournalFailClosedContract() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "TerminalSettingsUnreadableJournal-\(UUID().uuidString)",
                isDirectory: true
            )
        let undoStorageURL = directory.appendingPathComponent("last-undo.json")
        let pendingTransactionURL = directory
            .appendingPathComponent("pending-preference-transaction.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = RecordingDependencyLog()
        let executor = RecordingPreferenceExecutor(
            values: [:],
            allowedMutations: [],
            log: log
        )
        let journal = RecordingJournal(
            expectedURL: pendingTransactionURL,
            throwOnRead: true,
            log: log
        )
        func makeStore() -> PreferencesStore {
            PreferencesStore(
                executor: executor,
                restarter: RecordingRestarter(log: log),
                managementProvider: RecordingManagementProvider(log: log),
                powerExecutor: FailClosedPowerExecutor(log: log),
                journal: journal,
                appState: InMemoryApplicationState(),
                timeProvider: FixedTimeProvider(),
                identifierProvider: FixedIdentifierProvider(),
                undoStorageURL: undoStorageURL
            )
        }

        let firstCheckpoint = log.checkpoint()
        let firstStore = makeStore()
        let firstEvents = log.events(since: firstCheckpoint)
        try require(
            firstStore.hasPendingPreferenceTransaction && !firstStore.canUndo,
            "journal.read 抛错时初始化必须锁定且不能提供未知 Undo"
        )
        try require(
            firstStore.alert?.title.contains("无法读取") == true,
            "journal.read 抛错时缺少“无法读取”告警"
        )
        try require(
            PreferenceCatalog.items.allSatisfy { !firstStore.canModify($0) },
            "journal.read 抛错后仍有目录项可写"
        )
        try require(
            firstEvents.filter { event in
                if case .journalRead = event { return true }
                return false
            }.count == 1 &&
                !firstEvents.contains(where: { event in
                    if case .journalRemove = event { return true }
                    return false
                }),
            "首次初始化必须只读取一次且不得删除不可读 journal"
        )

        let secondCheckpoint = log.checkpoint()
        let secondStore = makeStore()
        let secondEvents = log.events(since: secondCheckpoint)
        try require(
            secondStore.hasPendingPreferenceTransaction && !secondStore.canUndo &&
                secondStore.alert?.title.contains("无法读取") == true,
            "不可读 journal 未在二次初始化时继续 fail closed"
        )
        try require(
            PreferenceCatalog.items.allSatisfy { !secondStore.canModify($0) },
            "二次初始化后不可读 journal 未继续锁定全部写入"
        )
        try require(
            secondEvents.filter { event in
                if case .journalRead = event { return true }
                return false
            }.count == 1 &&
                !secondEvents.contains(where: { event in
                    if case .journalRemove = event { return true }
                    return false
                }),
            "二次初始化必须重新读取且仍不得删除不可读 journal"
        )
        let allEvents = log.events(since: 0)
        try require(
            !allEvents.contains(where: { event in
                switch event {
                case .journalRemove, .journalPersist, .preferenceApply,
                        .preferenceRestore, .preferenceRestorePreservingExternalChanges,
                        .restart, .powerAuthorization, .powerApply, .powerRestore,
                        .powerRestorePreservingExternalChanges:
                    return true
                default:
                    return false
                }
            }),
            "不可读 journal 初始化路径产生了删除、持久化或系统副作用"
        )
    }

    private static func requireNoRecordedExternalEffects(
        _ events: [RecordingDependencyEvent],
        context: String
    ) throws {
        let forbidden = events.filter(\.isExternalMutationOrTransactionEffect)
        try require(
            forbidden.isEmpty,
            "\(context) 产生了禁止的外部效果：" +
                forbidden.map(\.description).joined(separator: "、")
        )
    }

    @MainActor
    private static func checkCustomizationStoreSurface() throws {
        let suiteName = "com.codex.TerminalSettings.checks.\(UUID().uuidString)"
        let undoDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TerminalSettingsChecks-\(UUID().uuidString)", isDirectory: true)
        let undoStorageURL = undoDirectory.appendingPathComponent("last-undo.json")
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CheckFailure.failed("无法创建自定义状态测试域")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            deleteDefaultsDomain(suiteName)
            try? FileManager.default.removeItem(at: undoDirectory)
        }

        defaults.set(true, forKey: "customization.keyboard.ultraFast.enabled")
        let store = PreferencesStore(
            appDefaults: defaults,
            undoStorageURL: undoStorageURL
        )
        guard let keyboard = PreferenceCatalog.items.first(where: {
            $0.id == "keyboard.ultraFast"
        }), let customization = keyboard.numericConfiguration,
              customization.parameters.count == 2 else {
            throw CheckFailure.failed("缺少按键重复自定义参数")
        }
        try require(store.isCustomizationEnabled(keyboard), "自定义模式未从独立状态域恢复")
        guard let dock = PreferenceCatalog.items.first(where: {
            $0.id == "dock.instantReveal"
        }) else {
            throw CheckFailure.failed("缺少程序坞显示延迟")
        }
        try require(!store.isCustomizationEnabled(dock), "不同功能项的自定义模式未隔离")

        let repeatInterval = customization.parameters[0]
        let initialDelay = customization.parameters[1]
        store.setCustomizationDraft(keyboard, parameter: repeatInterval, value: 3)
        store.setCustomizationDraft(keyboard, parameter: initialDelay, value: 15)
        try require(
            store.customizationDraft(for: keyboard, parameter: repeatInterval) == 3,
            "自定义草稿没有更新"
        )
        let persistedKeyboardDrafts = defaults.dictionary(
            forKey: "customization.keyboard.ultraFast.drafts"
        )
        try require(
            (persistedKeyboardDrafts?[repeatInterval.id] as? NSNumber)?.doubleValue == 3 &&
                (persistedKeyboardDrafts?[initialDelay.id] as? NSNumber)?.doubleValue == 15,
            "双参数草稿没有作为一个完整字典持久化"
        )
        let preview = store.previewCommands(for: keyboard)
        let customPreview = preview.first { $0.0 == "自定义（当前数值）" }?.1 ?? ""
        try require(customPreview.contains("KeyRepeat -int 3"), "命令预览未使用重复间隔草稿")
        try require(customPreview.contains("InitialKeyRepeat -int 15"), "命令预览未使用首次等待草稿")

        let reloadedStore = PreferencesStore(
            appDefaults: defaults,
            undoStorageURL: undoStorageURL
        )
        try require(reloadedStore.isCustomizationEnabled(keyboard), "自定义模式未跨启动保留")
        try require(
            reloadedStore.customizationDraft(for: keyboard, parameter: repeatInterval) == 3,
            "自定义草稿未跨启动保留"
        )

        let preferenceDomain = "com.codex.TerminalSettings.mode.\(UUID().uuidString)"
        let preferenceAddress = PreferenceAddress(
            domain: preferenceDomain,
            key: "Value"
        )
        let preferenceExecutor = PreferenceExecutor(commandTimeout: 5)
        defer { deleteDefaultsDomain(preferenceDomain) }
        try preferenceExecutor.apply(PreferenceMutation(
            address: preferenceAddress,
            value: .float(0.05)
        ))
        let modeItem = PreferenceItem(
            id: "checks.customizationMode",
            category: .dock,
            title: "自定义模式测试",
            detail: "仅验证模式开关不写入偏好",
            symbol: "slider.horizontal.3",
            control: .toggle(TogglePreference(
                readAddress: preferenceAddress,
                enabledValue: .float(0.18),
                enableMutations: [PreferenceMutation(
                    address: preferenceAddress,
                    value: .float(0.18)
                )],
                disableMutations: [PreferenceMutation(
                    address: preferenceAddress,
                    value: nil
                )]
            )),
            restartProcesses: [],
            effectHint: "测试",
            caution: .none,
            customization: PreferenceCustomization(
                detail: "测试",
                parameters: [NumericPreferenceParameter(
                    id: "value",
                    title: "值",
                    detail: "测试",
                    address: preferenceAddress,
                    range: 0...2,
                    step: 0.001,
                    presetValue: 0.18,
                    storage: .float,
                    unit: "",
                    precision: 3
                )]
            )
        )
        store.prepareCustomizationModeTest(
            modeItem,
            parentEnabled: true,
            currentValues: [preferenceAddress: .float(0.05)]
        )
        let valueBeforeModeChange = try preferenceExecutor.snapshots(
            for: [preferenceAddress]
        )

        store.setCustomizationEnabled(modeItem, enabled: true)
        try require(store.isCustomizationEnabled(modeItem), "未开启自定义编辑模式")
        try require(store.busyItemIDs.isEmpty, "自定义模式开关不应启动系统写入事务")
        try require(!store.canUndo, "纯界面自定义模式不应覆盖系统设置撤销槽")
        let valueAfterEnablingMode = try preferenceExecutor.snapshots(
            for: [preferenceAddress]
        )
        try require(
            valueAfterEnablingMode == valueBeforeModeChange,
            "开启自定义编辑模式意外改写了系统偏好"
        )
        try require(
            store.notice?.message.contains("当前系统值未更改") == true,
            "自定义模式切换提示没有明确无系统写入"
        )

        guard let modeParameter = modeItem.customization?.parameters.first else {
            throw CheckFailure.failed("自定义模式测试缺少数值参数")
        }
        try require(
            store.customizationCurrentValue(for: modeItem, parameter: modeParameter) ==
                .value(0.05, rawValue: .float(0.05)) &&
                store.customizationDraft(for: modeItem, parameter: modeParameter) == 0.18,
            "系统当前值与安全预设草稿没有保持独立"
        )
        store.loadCurrentCustomizationValues(modeItem)
        try require(
            store.customizationDraft(for: modeItem, parameter: modeParameter) == 0.05 &&
                store.customizationLoadRevision(for: modeItem) == 1,
            "载入系统当前值没有更新草稿或通知控件清除瞬态输入"
        )
        try require(
            store.busyItemIDs.isEmpty && !store.canUndo &&
                !store.hasPendingPreferenceTransaction,
            "载入当前值不应启动系统事务、journal 或占用撤销槽"
        )
        try require(
            store.notice?.message.contains("系统偏好未更改") == true,
            "载入当前值提示没有明确草稿与系统写入边界"
        )
        let valueAfterLoadingCurrent = try preferenceExecutor.snapshots(
            for: [preferenceAddress]
        )
        try require(
            valueAfterLoadingCurrent == valueBeforeModeChange,
            "载入当前值意外改写了系统偏好"
        )

        store.setCustomizationDraft(modeItem, parameter: modeParameter, value: 0.181)
        let valueAfterEditingDraft = try preferenceExecutor.snapshots(
            for: [preferenceAddress]
        )
        try require(
            valueAfterEditingDraft == valueBeforeModeChange,
            "调整自定义草稿意外改写了系统偏好"
        )
        store.prepareCustomizationModeTest(
            modeItem,
            parentEnabled: true,
            currentValues: [preferenceAddress: .float(0.04)]
        )
        try require(
            store.customizationCurrentValue(for: modeItem, parameter: modeParameter) ==
                .value(0.04, rawValue: .float(0.04)) &&
                store.customizationDraft(for: modeItem, parameter: modeParameter) == 0.181,
            "刷新外部当前值不应覆盖已有草稿"
        )
        store.loadCurrentCustomizationValues(modeItem)
        try require(
            store.customizationDraft(for: modeItem, parameter: modeParameter) == 0.04 &&
                store.customizationLoadRevision(for: modeItem) == 2,
            "第二次明确载入没有把最新读取值复制到草稿"
        )
        let valueAfterReloadingCurrent = try preferenceExecutor.snapshots(
            for: [preferenceAddress]
        )
        try require(
            valueAfterReloadingCurrent == valueBeforeModeChange,
            "刷新或再次载入当前值意外改写了系统偏好"
        )
        store.setCustomizationInputError(
            modeItem,
            parameter: modeParameter,
            message: "精确输入尚未有效提交"
        )
        try require(
            !store.canApplyCustomization(modeItem),
            "无效精确输入仍允许应用旧草稿"
        )
        store.setCustomizationInputError(modeItem, parameter: modeParameter, message: nil)
        try require(
            store.canApplyCustomization(modeItem),
            "清除输入错误后合法草稿仍不可应用"
        )

        store.applyCustomization(modeItem)
        try waitUntil("外部冲突检查未完成") {
            !store.isWorking
        }
        try require(
            store.alert != nil && !store.canUndo &&
                !store.hasPendingPreferenceTransaction,
            "刷新后外部修改没有在首笔写入前中止"
        )
        let valueAfterConflict = try preferenceExecutor.snapshots(
            for: [preferenceAddress]
        )
        try require(
            valueAfterConflict == valueBeforeModeChange,
            "冲突的自定义应用覆盖了外部较新值"
        )
        store.alert = nil

        store.setCustomizationEnabled(modeItem, enabled: false)
        try require(!store.isCustomizationEnabled(modeItem), "未关闭自定义编辑模式")
        try require(store.busyItemIDs.isEmpty, "关闭自定义模式不应启动系统写入事务")
        let valueAfterDisablingMode = try preferenceExecutor.snapshots(
            for: [preferenceAddress]
        )
        try require(
            valueAfterDisablingMode == valueBeforeModeChange,
            "关闭自定义编辑模式意外应用了安全预设"
        )

        store.setToggle(modeItem, enabled: true)
        try waitUntil("目录外偏好白名单检查未完成") {
            !store.isWorking
        }
        try require(
            store.alert?.message.contains("白名单") == true,
            "目录外测试地址没有被持久化记录白名单拒绝"
        )
        try preferenceExecutor.verify(valueBeforeModeChange)
        let pendingJournalURL = undoDirectory
            .appendingPathComponent("pending-preference-transaction.json")
        try require(
            !FileManager.default.fileExists(atPath: pendingJournalURL.path),
            "目录外事务失败后残留写前恢复日志"
        )
        try require(
            !store.canUndo && !FileManager.default.fileExists(atPath: undoStorageURL.path),
            "目录外事务不应创建可执行撤销记录"
        )
    }

    @MainActor
    private static func waitUntil(
        _ failureMessage: String,
        timeout: TimeInterval = 5,
        condition: () -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        try require(condition(), failureMessage)
    }

    private static func checkExecutorAndSnapshots() throws {
        try require(
            !PreferenceValue.bool(false).matches(raw: "garbage"),
            "未知文字不能被当作 false"
        )
        try require(
            !PreferenceValue.integer(1).matches(.float(1)),
            "不同 plist 标量类型不能视为相同"
        )
        try require(
            !PreferenceValue.float(0.05).matches(.float(0.05005)) &&
                PreferenceValue.float(0.05).matches(.float(0.05000000001)) &&
                PreferenceValue.float(0.18).matches(.float(Double(Float(0.18)))),
            "浮点快照比较必须区分真实外部改值并容忍微小序列化误差"
        )
        let executor = PreferenceExecutor(commandTimeout: 5)
        let domain = "com.codex.TerminalSettings.verify.\(UUID().uuidString)"
        let addresses = [
            PreferenceAddress(domain: domain, key: "Boolean"),
            PreferenceAddress(domain: domain, key: "Integer"),
            PreferenceAddress(domain: domain, key: "Float"),
            PreferenceAddress(domain: domain, key: "Text"),
            PreferenceAddress(domain: domain, key: "CurrentHost", hostScope: .currentHost),
            PreferenceAddress(domain: domain, key: "LargeText")
        ]
        let before = try executor.snapshots(for: addresses)

        defer {
            for address in addresses {
                try? executor.apply(PreferenceMutation(address: address, value: nil))
            }
            deleteDefaultsDomain(domain)
            deleteDefaultsDomain(domain, currentHost: true)
        }

        let mutations = [
            PreferenceMutation(address: addresses[0], value: .bool(true)),
            PreferenceMutation(address: addresses[1], value: .integer(7)),
            PreferenceMutation(address: addresses[2], value: .float(0.18)),
            PreferenceMutation(address: addresses[3], value: .string("引号 ' 与中文")),
            PreferenceMutation(address: addresses[4], value: .bool(true)),
            PreferenceMutation(
                address: addresses[5],
                value: .string(String(repeating: "x", count: 128 * 1_024))
            )
        ]
        for mutation in mutations { try executor.apply(mutation) }

        let expected = mutations.map { PreferenceSnapshot(address: $0.address, value: $0.value) }
        try executor.verify(expected)
        let after = try executor.snapshots(for: addresses)
        try executor.ensureUnchanged(since: after)

        try executor.apply(PreferenceMutation(address: addresses[0], value: .string("true")))
        var detectedConflict = false
        do {
            try executor.ensureUnchanged(since: after)
        } catch PreferenceExecutorError.conflict {
            detectedConflict = true
        }
        try require(detectedConflict, "外部修改的值或标量类型冲突未被检测")

        let booleanBefore = before.filter { $0.address == addresses[0] }
        let booleanAfter = after.filter { $0.address == addresses[0] }
        let preservedConflicts = try executor.restorePreservingExternalChanges(
            booleanBefore,
            whenCurrentMatches: [booleanBefore, booleanAfter]
        )
        try require(
            preservedConflicts == [addresses[0]],
            "冲突感知回滚没有报告外部第三种值"
        )
        let preservedValue = try executor.snapshots(for: [addresses[0]]).first?.value
        try require(
            preservedValue == .string("true"),
            "冲突感知回滚覆盖了外部第三种值"
        )

        try executor.apply(PreferenceMutation(address: addresses[0], value: .bool(true)))
        let safeConflicts = try executor.restorePreservingExternalChanges(
            booleanBefore,
            whenCurrentMatches: [booleanBefore, booleanAfter]
        )
        try require(safeConflicts.isEmpty, "已知事务状态不应被视为外部冲突")
        try executor.verify(booleanBefore)

        try executor.restore(before)
        try executor.verify(before)

        let preview = PreferenceMutation(
            address: addresses[3],
            value: .string("引号 ' 与中文")
        ).command
        try require(preview.contains("'\\''"), "命令预览没有安全转义单引号")

        let currentHostPreview = PreferenceMutation(
            address: addresses[4],
            value: .bool(true)
        ).command
        try require(
            currentHostPreview.hasPrefix("defaults -currentHost write"),
            "当前主机命令预览缺少 -currentHost"
        )
    }

    private static func deleteDefaultsDomain(_ domain: String, currentHost: Bool = false) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = (currentHost ? ["-currentHost"] : []) + ["delete", domain]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Best-effort cleanup must not hide the original test result.
        }

        // `defaults delete <domain>` can leave a zero-key plist behind. These
        // domains are random and owned only by this test, so remove their empty
        // backing files as the final cleanup step.
        let preferencesDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        if currentHost {
            let byHostDirectory = preferencesDirectory
                .appendingPathComponent("ByHost", isDirectory: true)
            let matchingFiles = (try? FileManager.default.contentsOfDirectory(
                at: byHostDirectory,
                includingPropertiesForKeys: nil
            ))?.filter {
                $0.lastPathComponent.hasPrefix("\(domain).") &&
                    $0.pathExtension == "plist"
            } ?? []
            for file in matchingFiles {
                try? FileManager.default.removeItem(at: file)
            }
        } else {
            try? FileManager.default.removeItem(
                at: preferencesDirectory.appendingPathComponent("\(domain).plist")
            )
        }
    }

    private static func checkPowerSettingsParsing() throws {
        let fixture = """
        Battery Power:
         ttyskeepawake        0
         proximitywake        1
         unrelated            text
        AC Power:
         ttyskeepawake        1
         proximitywake        1
         acwake               0
        UPS Power:
         ttyskeepawake        1
        """
        let profiles = PowerSettingsExecutor.parseProfiles(fixture)
        try require(
            profiles[.battery]?["ttyskeepawake"] == 0,
            "未解析电池电源的 pmset 值"
        )
        try require(
            profiles[.charger]?["acwake"] == 0,
            "未解析电源适配器的 pmset 值"
        )
        try require(
            profiles[.ups]?["ttyskeepawake"] == 1,
            "未解析 UPS 的 pmset 值"
        )
        try require(
            profiles[.battery]?["unrelated"] == nil,
            "非整数 pmset 值不应进入受控状态"
        )

        let executor = PowerSettingsExecutor()
        let current = try executor.snapshots(for: [
            "ttyskeepawake", "proximitywake", "acwake"
        ])
        try require(!current.isEmpty, "验证环境至少应支持一项高级电源能力")
        try require(
            current.allSatisfy {
                !$0.values.isEmpty && $0.values.allSatisfy { [0, 1].contains($0.value) }
            },
            "高级电源能力必须读取为每来源布尔值"
        )
    }

    private static func checkUndoEncoding() throws {
        let address = PreferenceAddress(domain: "example.domain", key: "ExampleKey")
        let record = UndoRecord(
            title: "测试撤销",
            before: [PreferenceSnapshot(address: address, value: nil)],
            after: [PreferenceSnapshot(address: address, value: .bool(true))],
            restartProcesses: ["Finder"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let powerSnapshot = PowerSettingSnapshot(
            key: "ttyskeepawake",
            values: [PowerSourceValue(source: .charger, value: 1)]
        )
        let powerRecord = UndoRecord(
            title: "测试高级撤销",
            before: [],
            after: [],
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            powerBefore: [powerSnapshot],
            powerAfter: [PowerSettingSnapshot(
                key: "ttyskeepawake",
                values: [PowerSourceValue(source: .charger, value: 0)]
            )]
        )
        let envelope = PersistedUndoEnvelope(schemaVersion: 4, record: powerRecord)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PersistedUndoEnvelope.self, from: data)
        try require(decoded.schemaVersion == 4, "撤销记录 schemaVersion 编码失败")
        try require(
            decoded.record.powerBefore == powerRecord.powerBefore,
            "高级撤销前快照编码失败"
        )
        try require(
            decoded.record.powerAfter == powerRecord.powerAfter,
            "高级撤销后快照编码失败"
        )

        let recoveryBaseline = PreferenceRecoveryBaseline(
            itemID: "keyboard.ultraFast",
            before: [PreferenceSnapshot(address: address, value: .integer(6))],
            lastApplied: [PreferenceSnapshot(address: address, value: .integer(1))],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let recoveryRecord = UndoRecord(
            title: "测试恢复基线",
            before: recoveryBaseline.before,
            after: recoveryBaseline.lastApplied,
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            recoveryItemIDs: [recoveryBaseline.itemID],
            recoveryBefore: [:],
            recoveryAfter: [recoveryBaseline.itemID: recoveryBaseline]
        )
        let recoveryData = try encoder.encode(
            PersistedUndoEnvelope(schemaVersion: 4, record: recoveryRecord)
        )
        let decodedRecovery = try decoder.decode(PersistedUndoEnvelope.self, from: recoveryData)
        try require(
            decodedRecovery.record.recoveryAfter?[recoveryBaseline.itemID] == recoveryBaseline,
            "schema 4 未保留接管前恢复基线"
        )
        let pendingData = try encoder.encode(
            PersistedPendingPreferenceEnvelope(schemaVersion: 1, record: recoveryRecord)
        )
        let decodedPending = try decoder.decode(
            PersistedPendingPreferenceEnvelope.self,
            from: pendingData
        )
        try require(
            decodedPending.schemaVersion == 1 &&
                decodedPending.record.before == recoveryRecord.before &&
                decodedPending.record.after == recoveryRecord.after,
            "写前恢复日志没有完整保留事务前后快照"
        )
        let journalURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TerminalSettings-journal-\(UUID().uuidString).json")
        defer { PreferenceTransactionJournal.clear(journalURL) }
        try PreferenceTransactionJournal.write(recoveryRecord, to: journalURL)
        let loadedJournal = try PreferenceTransactionJournal.load(from: journalURL)
        try require(
            loadedJournal?.before == recoveryRecord.before &&
                loadedJournal?.after == recoveryRecord.after &&
                loadedJournal?.recoveryAfter == recoveryRecord.recoveryAfter,
            "写前恢复日志真实文件往返失败"
        )
        PreferenceTransactionJournal.clear(journalURL)
        try require(
            !FileManager.default.fileExists(atPath: journalURL.path),
            "写前恢复日志清理失败"
        )

        let powerBefore = PowerSettingSnapshot(
            key: "ttyskeepawake",
            values: [
                PowerSourceValue(source: .battery, value: 1),
                PowerSourceValue(source: .charger, value: 1)
            ]
        )
        let powerAfter = PowerSettingSnapshot(
            key: "ttyskeepawake",
            values: [
                PowerSourceValue(source: .battery, value: 0),
                PowerSourceValue(source: .charger, value: 0)
            ]
        )
        let powerJournalRecord = UndoRecord(
            title: "测试高级写前恢复",
            before: [],
            after: [],
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            powerBefore: [powerBefore],
            powerAfter: [powerAfter]
        )
        let powerJournalURL = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent("TerminalSettings-power-journal-\(UUID().uuidString).json")
        defer { PreferenceTransactionJournal.clear(powerJournalURL) }
        try PreferenceTransactionJournal.write(powerJournalRecord, to: powerJournalURL)
        let loadedPowerJournal = try PreferenceTransactionJournal.load(from: powerJournalURL)
        try require(
            loadedPowerJournal?.powerBefore == [powerBefore] &&
                loadedPowerJournal?.powerAfter == [powerAfter],
            "高级电源写前恢复日志真实文件往返失败"
        )

        func requireInvalidJournal(
            _ invalidRecord: UndoRecord,
            schemaVersion: Int = 1,
            _ message: String
        ) throws {
            let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("TerminalSettings-invalid-journal-\(UUID().uuidString).json")
            defer { PreferenceTransactionJournal.clear(url) }
            let invalidEnvelope = PersistedPendingPreferenceEnvelope(
                schemaVersion: schemaVersion,
                record: invalidRecord
            )
            let invalidData = try encoder.encode(invalidEnvelope)
            try invalidData.write(to: url, options: .atomic)
            do {
                _ = try PreferenceTransactionJournal.load(from: url)
                throw CheckFailure.failed(message)
            } catch let failure as CheckFailure {
                throw failure
            } catch {
                // Expected: a pending journal is a strict, mutually exclusive
                // ordinary-or-power transaction rather than a best-effort log.
            }
        }

        let emptyRecord = UndoRecord(
            title: "空事务",
            before: [],
            after: [],
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try requireInvalidJournal(emptyRecord, "空写前恢复事务未被拒绝")
        let mixedRecord = UndoRecord(
            title: "混合事务",
            before: record.before,
            after: record.after,
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            powerBefore: [powerBefore],
            powerAfter: [powerAfter]
        )
        try requireInvalidJournal(mixedRecord, "普通与高级混合事务未被拒绝")
        let otherAddress = PreferenceAddress(domain: "example.domain", key: "OtherKey")
        let mismatchedOrdinary = UndoRecord(
            title: "地址不一致",
            before: record.before,
            after: [PreferenceSnapshot(address: otherAddress, value: .bool(true))],
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try requireInvalidJournal(mismatchedOrdinary, "前后地址集合不一致未被拒绝")
        let mismatchedPower = UndoRecord(
            title: "电源来源不一致",
            before: [],
            after: [],
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            powerBefore: [powerBefore],
            powerAfter: [PowerSettingSnapshot(
                key: powerAfter.key,
                values: [PowerSourceValue(source: .battery, value: 0)]
            )]
        )
        try requireInvalidJournal(mismatchedPower, "前后电源来源集合不一致未被拒绝")
        let duplicatePower = UndoRecord(
            title: "重复电源来源",
            before: [],
            after: [],
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            powerBefore: [PowerSettingSnapshot(
                key: powerBefore.key,
                values: [
                    PowerSourceValue(source: .charger, value: 1),
                    PowerSourceValue(source: .charger, value: 1)
                ]
            )],
            powerAfter: [powerAfter]
        )
        try requireInvalidJournal(duplicatePower, "重复电源来源未被拒绝")
        let nonBooleanPower = UndoRecord(
            title: "非布尔电源值",
            before: [],
            after: [],
            restartProcesses: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            powerBefore: [PowerSettingSnapshot(
                key: powerBefore.key,
                values: [
                    PowerSourceValue(source: .battery, value: 2),
                    PowerSourceValue(source: .charger, value: 1)
                ]
            )],
            powerAfter: [powerAfter]
        )
        try requireInvalidJournal(nonBooleanPower, "非布尔电源值未被拒绝")
        try requireInvalidJournal(powerJournalRecord, schemaVersion: 2, "未知 journal schema 未被拒绝")

        let partialPower = PowerSettingSnapshot(
            key: powerBefore.key,
            values: [
                PowerSourceValue(source: .battery, value: 0),
                PowerSourceValue(source: .charger, value: 1)
            ]
        )
        try require(
            PowerSettingsExecutor.recoveryConflicts(
                allowedStates: [[powerBefore], [powerAfter]],
                current: [partialPower]
            ).isEmpty,
            "跨电源来源的部分写入状态应允许恢复"
        )
        let missingSource = PowerSettingSnapshot(
            key: powerBefore.key,
            values: [PowerSourceValue(source: .battery, value: 0)]
        )
        try require(
            !PowerSettingsExecutor.recoveryConflicts(
                allowedStates: [[powerBefore], [powerAfter]],
                current: [missingSource]
            ).isEmpty,
            "缺失电源来源的状态未被恢复前置检查拒绝"
        )
        let thirdValue = PowerSettingSnapshot(
            key: powerBefore.key,
            values: [
                PowerSourceValue(source: .battery, value: 2),
                PowerSourceValue(source: .charger, value: 1)
            ]
        )
        try require(
            !PowerSettingsExecutor.recoveryConflicts(
                allowedStates: [[powerBefore], [powerAfter]],
                current: [thirdValue]
            ).isEmpty,
            "高级电源第三种外部值未被恢复前置检查拒绝"
        )

        let schema2Data = try encoder.encode(
            PersistedUndoEnvelope(schemaVersion: 2, record: record)
        )
        let schema2 = try decoder.decode(PersistedUndoEnvelope.self, from: schema2Data)
        try require(
            schema2.record.before == record.before && schema2.record.powerBefore == nil,
            "普通 schema 2 撤销记录兼容失败"
        )

        let legacyAddressData = Data(#"{"domain":"legacy.domain","key":"LegacyKey"}"#.utf8)
        let legacyAddress = try JSONDecoder().decode(PreferenceAddress.self, from: legacyAddressData)
        try require(
            legacyAddress.hostScope == .currentUser,
            "1.1.0 撤销记录的偏好地址迁移失败"
        )

        let legacyRecordData = Data(#"""
        {
            "title":"旧撤销记录",
            "before":[],
            "after":[],
            "restartProcesses":[],
            "createdAt":"2023-11-14T22:13:20Z"
        }
        """#.utf8)
        let legacyRecord = try decoder.decode(UndoRecord.self, from: legacyRecordData)
        try require(
            legacyRecord.customizationBefore == nil &&
                legacyRecord.customizationAfter == nil &&
                legacyRecord.powerBefore == nil &&
                legacyRecord.powerAfter == nil,
            "旧撤销记录缺少扩展状态时应向后兼容"
        )

        let legacyEnvelopeData = Data(#"""
        {
            "schemaVersion":1,
            "record":{
                "title":"1.1.0 撤销记录",
                "before":[{
                    "address":{"domain":"legacy.domain","key":"LegacyKey"},
                    "value":null
                }],
                "after":[{
                    "address":{"domain":"legacy.domain","key":"LegacyKey"},
                    "value":null
                }],
                "restartProcesses":[],
                "createdAt":"2023-11-14T22:13:20Z"
            }
        }
        """#.utf8)
        let legacyEnvelope = try decoder.decode(
            PersistedUndoEnvelope.self,
            from: legacyEnvelopeData
        )
        try require(legacyEnvelope.schemaVersion == 1, "schema 1 envelope 解码失败")
        try require(
            legacyEnvelope.record.before.first?.address.hostScope == .currentUser,
            "schema 1 envelope 的主机作用域迁移失败"
        )
    }
}
