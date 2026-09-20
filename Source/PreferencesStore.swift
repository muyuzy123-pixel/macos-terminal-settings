import AppKit
import CoreFoundation
import Darwin
import Foundation

struct ProcessResult {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

enum PreferenceExecutorError: LocalizedError, DisplayMessageError {
    case launch(LocalizedText)
    case command(String, LocalizedText)
    case timeout(String)
    case verification(LocalizedText)
    case conflict(LocalizedText)

    var errorDescription: String? { displayMessage.source }

    var displayMessage: LocalizedText {
        switch self {
        case .launch(let message):
            return L("无法启动系统工具：\(message)")
        case .command(let command, let message):
            return L("命令执行失败：\(command)\n\(message)")
        case .timeout(let command):
            return L("系统工具响应超时：\(command)")
        case .verification(let message):
            return L("写入后的状态校验失败：\(message)")
        case .conflict(let message):
            return message
        }
    }
}

private final class LockedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func store(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    func load() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

enum PreferenceTransactionJournal {
    static func write(_ record: UndoRecord, to url: URL) throws {
        guard isStructurallyValid(record) else {
            throw PreferenceExecutorError.verification(L("拒绝写入结构无效的恢复日志"))
        }
        let envelope = PersistedPendingPreferenceEnvelope(schemaVersion: 1, record: record)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> UndoRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(PersistedPendingPreferenceEnvelope.self, from: data)
        guard envelope.schemaVersion == 1,
              isStructurallyValid(envelope.record) else {
            throw PreferenceExecutorError.verification(L("写前恢复日志结构无效"))
        }
        return envelope.record
    }

    static func isStructurallyValid(_ record: UndoRecord) -> Bool {
        let beforeAddresses = Set(record.before.map(\.address))
        let afterAddresses = Set(record.after.map(\.address))
        let ordinaryIsValid = !beforeAddresses.isEmpty &&
            record.before.count == beforeAddresses.count &&
            record.after.count == afterAddresses.count &&
            beforeAddresses == afterAddresses &&
            (record.powerBefore?.isEmpty ?? true) &&
            (record.powerAfter?.isEmpty ?? true)
        let powerIsValid = record.before.isEmpty &&
            record.after.isEmpty &&
            validPowerPair(before: record.powerBefore, after: record.powerAfter)
        return ordinaryIsValid != powerIsValid
    }

    private static func validPowerPair(
        before: [PowerSettingSnapshot]?,
        after: [PowerSettingSnapshot]?
    ) -> Bool {
        guard let before, let after, !before.isEmpty, before.count == after.count else {
            return false
        }
        func indexed(
            _ snapshots: [PowerSettingSnapshot]
        ) -> [String: Set<PowerSource>]? {
            var result: [String: Set<PowerSource>] = [:]
            for snapshot in snapshots {
                guard !snapshot.key.isEmpty,
                      !snapshot.values.isEmpty,
                      result[snapshot.key] == nil else { return nil }
                let sources = Set(snapshot.values.map(\.source))
                guard sources.count == snapshot.values.count,
                      snapshot.values.allSatisfy({ [0, 1].contains($0.value) }) else {
                    return nil
                }
                result[snapshot.key] = sources
            }
            return result
        }
        guard let beforeIndex = indexed(before), let afterIndex = indexed(after) else {
            return false
        }
        return beforeIndex == afterIndex
    }

    @discardableResult
    static func clear(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}

enum PersistedRecordPolicy {
    static func isAllowed(_ record: UndoRecord) -> Bool {
        guard PreferenceTransactionJournal.isStructurallyValid(record) else {
            return false
        }
        let regularItems = PreferenceCatalog.items.filter { !$0.requiresAdministrator }
        let allowedAddresses = Set(regularItems.flatMap(\.allAddresses))
        let recordAddresses = Set((record.before + record.after).map(\.address))
        let allowedPowerKeys = Set(PreferenceCatalog.items.compactMap(\.privilegedKey))
        let recordPowerSnapshots = (record.powerBefore ?? []) + (record.powerAfter ?? [])
        let allowedRestartProcesses: Set<String> = ["Dock", "Finder"]

        guard record.restartProcesses.allSatisfy(allowedRestartProcesses.contains),
              recordAddresses.isSubset(of: allowedAddresses),
              recordPowerSnapshots.allSatisfy({ snapshot in
                  allowedPowerKeys.contains(snapshot.key) &&
                      !snapshot.values.isEmpty &&
                      Set(snapshot.values.map(\.source)).count == snapshot.values.count &&
                      snapshot.values.allSatisfy { [0, 1].contains($0.value) }
              }) else {
            return false
        }

        if recordPowerSnapshots.isEmpty {
            let affectedItems = regularItems.filter {
                !Set($0.allAddresses).isDisjoint(with: recordAddresses)
            }
            let allowedForAffectedItems = Set(affectedItems.flatMap(\.restartProcesses))
            guard Set(record.restartProcesses).isSubset(of: allowedForAffectedItems) else {
                return false
            }
        } else if !record.restartProcesses.isEmpty {
            return false
        }

        let catalogByID = Dictionary(
            uniqueKeysWithValues: PreferenceCatalog.items.map { ($0.id, $0) }
        )
        let customizationBeforeIDs = Set(record.customizationBefore?.keys.map { $0 } ?? [])
        let customizationAfterIDs = Set(record.customizationAfter?.keys.map { $0 } ?? [])
        let customizationIDs = customizationBeforeIDs.union(customizationAfterIDs)
        guard customizationIDs.allSatisfy({ catalogByID[$0]?.numericConfiguration != nil }) else {
            return false
        }

        let recoveryBeforeIDs = Set(record.recoveryBefore?.keys.map { $0 } ?? [])
        let recoveryAfterIDs = Set(record.recoveryAfter?.keys.map { $0 } ?? [])
        let recoveryIDs = Set(record.recoveryItemIDs ?? [])
            .union(recoveryBeforeIDs)
            .union(recoveryAfterIDs)
        for itemID in recoveryIDs {
            guard let item = catalogByID[itemID],
                  case .restoreBaseline = item.recovery.strategy else {
                return false
            }
            for baseline in [record.recoveryBefore?[itemID], record.recoveryAfter?[itemID]]
                .compactMap({ $0 }) {
                let expected = Set(item.allAddresses)
                guard baseline.itemID == itemID,
                      Set(baseline.before.map { $0.address }) == expected,
                      Set(baseline.lastApplied.map { $0.address }) == expected else {
                    return false
                }
            }
        }
        return true
    }
}

private struct DefaultsDomain: Hashable {
    let name: String
    let hostScope: PreferenceHostScope

    init(_ address: PreferenceAddress) {
        name = address.domain
        hostScope = address.hostScope
    }
}

final class PreferenceExecutor: PreferenceExecuting, ProcessRestarting, @unchecked Sendable {
    private let defaultsURL = URL(fileURLWithPath: "/usr/bin/defaults")
    private let killallURL = URL(fileURLWithPath: "/usr/bin/killall")
    private let commandTimeout: TimeInterval

    init(commandTimeout: TimeInterval = 5) {
        self.commandTimeout = commandTimeout
    }

    func snapshots(for addresses: [PreferenceAddress]) throws -> [PreferenceSnapshot] {
        let values = try readValues(for: addresses)
        return addresses.map { PreferenceSnapshot(address: $0, value: values[$0]) }
    }

    func verify(_ expected: [PreferenceSnapshot]) throws {
        let current = try snapshots(for: expected.map(\.address))
        let currentByAddress = Dictionary(uniqueKeysWithValues: current.map { ($0.address, $0.value) })
        for snapshot in expected {
            let actual = currentByAddress[snapshot.address] ?? nil
            let matches: Bool
            switch (snapshot.value, actual) {
            case (nil, nil):
                matches = true
            case (.some(let expectedValue), .some(let actualValue)):
                matches = expectedValue.matches(actualValue)
            default:
                matches = false
            }
            guard matches else {
                let expectedValue = snapshot.value.map { LocalizedText(verbatim: $0.displayValue) } ?? L("未设置")
                let actualValue = actual.map { LocalizedText(verbatim: $0.displayValue) } ?? L("未设置")
                throw PreferenceExecutorError.verification(
                    L("\(snapshot.address.displayPath)：期望 \(expectedValue)，实际 \(actualValue)")
                )
            }
        }
    }

    func ensureUnchanged(since expected: [PreferenceSnapshot]) throws {
        do {
            try verify(expected)
        } catch {
            throw PreferenceExecutorError.conflict(
                L("检测到偏好已被其他 App 或命令修改。为避免覆盖较新的值，本次操作未执行。请刷新状态后再决定。")
            )
        }
    }

    /// Verifies an entire transaction before writing. Each address may be in
    /// any one of the supplied transaction states, which also makes an
    /// interrupted multi-key write safely recoverable.
    func ensureCurrentMatchesAny(
        _ allowedStates: [[PreferenceSnapshot]],
        operation: LocalizedText
    ) throws {
        var allowedByAddress: [PreferenceAddress: [PreferenceValue?]] = [:]
        for state in allowedStates {
            for snapshot in state {
                allowedByAddress[snapshot.address, default: []].append(snapshot.value)
            }
        }
        let addresses = Array(allowedByAddress.keys)
        let current = try snapshots(for: addresses)
        for snapshot in current {
            let allowedValues = allowedByAddress[snapshot.address] ?? []
            guard allowedValues.contains(where: { valuesMatch($0, snapshot.value) }) else {
                throw PreferenceExecutorError.conflict(
                    L("检测到 \(snapshot.address.displayPath) 已被外部修改；为避免覆盖较新的值，\(operation)未执行。")
                )
            }
        }
    }

    /// Reads each defaults domain once, even when several settings share it.
    /// This keeps launch work bounded to the small number of domains in the catalog.
    func readValues(for addresses: [PreferenceAddress]) throws -> [PreferenceAddress: PreferenceValue] {
        let uniqueDomains = Set(addresses.map(DefaultsDomain.init))
        var domains: [DefaultsDomain: [String: Any]] = [:]
        for domain in uniqueDomains {
            domains[domain] = try exportDomain(domain.name, hostScope: domain.hostScope)
        }

        var result: [PreferenceAddress: PreferenceValue] = [:]
        for address in addresses {
            guard let rawValue = domains[DefaultsDomain(address)]?[address.key] else { continue }
            guard let value = preferenceValue(from: rawValue) else {
                throw PreferenceExecutorError.verification(
                    L("\(address.displayPath) 当前不是受支持的布尔、整数、浮点或文字值；为避免丢失原值，已停止修改")
                )
            }
            result[address] = value
        }
        return result
    }

    func apply(_ mutation: PreferenceMutation) throws {
        if mutation.value == nil {
            let existing = try readValues(for: [mutation.address])
            if existing[mutation.address] == nil { return }
        }

        var arguments = mutation.address.hostScope == .currentHost ? ["-currentHost"] : []
        if let value = mutation.value {
            arguments.append(contentsOf: ["write", mutation.address.domain, mutation.address.key])
            arguments.append(contentsOf: value.defaultsArguments)
        } else {
            arguments.append(contentsOf: ["delete", mutation.address.domain, mutation.address.key])
        }

        let result = try run(defaultsURL, arguments)
        guard result.status == 0 else {
            throw PreferenceExecutorError.command(
                mutation.command,
                LocalizedText(verbatim: result.standardError.isEmpty ? result.standardOutput : result.standardError)
            )
        }
    }

    func restore(_ snapshots: [PreferenceSnapshot]) throws {
        for snapshot in snapshots {
            try apply(PreferenceMutation(address: snapshot.address, value: snapshot.value))
        }
    }

    /// Restores only values that are still in one of the states owned by this
    /// transaction. A third state is assumed to be a newer external change and
    /// is deliberately preserved.
    func restorePreservingExternalChanges(
        _ target: [PreferenceSnapshot],
        whenCurrentMatches allowedStates: [[PreferenceSnapshot]]
    ) throws -> [PreferenceAddress] {
        var allowedByAddress: [PreferenceAddress: [PreferenceValue?]] = [:]
        for state in allowedStates {
            for snapshot in state {
                allowedByAddress[snapshot.address, default: []].append(snapshot.value)
            }
        }

        var conflicts: [PreferenceAddress] = []
        var seen = Set<PreferenceAddress>()
        for snapshot in target where seen.insert(snapshot.address).inserted {
            let current = try snapshots(for: [snapshot.address]).first?.value ?? nil
            let allowedValues = allowedByAddress[snapshot.address] ?? []
            guard allowedValues.contains(where: { valuesMatch($0, current) }) else {
                conflicts.append(snapshot.address)
                continue
            }
            try restore([snapshot])
            try verify([snapshot])
        }
        return conflicts
    }

    func restart(_ processNames: [String]) {
        for processName in Set(processNames) {
            _ = try? run(killallURL, [processName])
        }
    }

    private func exportDomain(
        _ domain: String,
        hostScope: PreferenceHostScope
    ) throws -> [String: Any] {
        var arguments = hostScope == .currentHost ? ["-currentHost"] : []
        arguments.append(contentsOf: ["export", domain, "-"])
        let result = try run(defaultsURL, arguments)
        if result.status != 0 {
            let diagnostic = result.standardError.isEmpty ? result.standardOutput : result.standardError
            let normalized = diagnostic.lowercased()
            if normalized.contains("does not exist") || normalized.contains("not found") {
                // An absent preference domain is equivalent to having no explicit values.
                return [:]
            }
            let scope = hostScope == .currentHost ? " -currentHost" : ""
            throw PreferenceExecutorError.command(
                "defaults\(scope) export \(domain) -",
                diagnostic.isEmpty ? L("未知读取错误") : LocalizedText(verbatim: diagnostic)
            )
        }

        guard let data = result.standardOutput.data(using: .utf8),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let dictionary = propertyList as? [String: Any] else {
            if result.standardOutput.isEmpty {
                return [:]
            }
            let scope = hostScope == .currentHost ? " -currentHost" : ""
            throw PreferenceExecutorError.command(
                "defaults\(scope) export \(domain) -",
                L("系统返回了无法解析的属性列表")
            )
        }

        return dictionary
    }

    private func preferenceValue(from rawValue: Any) -> PreferenceValue? {
        if let string = rawValue as? String {
            return .string(string)
        }
        if let number = rawValue as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if CFNumberIsFloatType(number) {
                return .float(number.doubleValue)
            }
            return .integer(number.intValue)
        }
        return nil
    }

    private func valuesMatch(_ expected: PreferenceValue?, _ actual: PreferenceValue?) -> Bool {
        switch (expected, actual) {
        case (nil, nil):
            return true
        case (.some(let expectedValue), .some(let actualValue)):
            return expectedValue.matches(actualValue)
        default:
            return false
        }
    }

    private func run(_ executableURL: URL, _ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            throw PreferenceExecutorError.launch(error.displayMessage)
        }

        // Drain both pipes while the process is running. Waiting first can deadlock
        // when `defaults export NSGlobalDomain -` fills the stdout pipe buffer.
        let outputData = LockedDataBox()
        let errorData = LockedDataBox()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            outputData.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorData.store(errorPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        if completion.wait(timeout: .now() + commandTimeout) == .timedOut {
            process.terminate()
            if completion.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 0.5)
            }
            _ = readers.wait(timeout: .now() + 1)
            let command = ([executableURL.path] + arguments).joined(separator: " ")
            throw PreferenceExecutorError.timeout(command)
        }
        readers.wait()

        let output = String(data: outputData.load(), encoding: .utf8) ?? ""
        let error = String(data: errorData.load(), encoding: .utf8) ?? ""
        return ProcessResult(
            status: process.terminationStatus,
            standardOutput: output.trimmingCharacters(in: .whitespacesAndNewlines),
            standardError: error.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct AppAlert: Identifiable {
    let id: UUID
    let title: LocalizedText
    let message: LocalizedText

    init(id: UUID = UUID(), title: LocalizedText, message: LocalizedText) {
        self.id = id
        self.title = title
        self.message = message
    }
}

struct AppNotice: Identifiable {
    let id: UUID
    let message: LocalizedText
    let canUndo: Bool

    init(id: UUID = UUID(), message: LocalizedText, canUndo: Bool) {
        self.id = id
        self.message = message
        self.canUndo = canUndo
    }
}

struct PreferenceChangeFailure: LocalizedError, DisplayMessageError {
    let message: LocalizedText
    var helperOutcomeIsUnknown = false
    var errorDescription: String? { message.source }
    var displayMessage: LocalizedText { message }
}

@MainActor
final class PreferencesStore: ObservableObject {
    @Published private(set) var toggleValues: [String: Bool] = [:]
    @Published private(set) var choiceValues: [String: String] = [:]
    @Published private(set) var customChoiceValues: [String: String] = [:]
    @Published private(set) var customizationModes: [String: Bool] = [:]
    @Published private(set) var customizationDrafts: [String: [String: Double]] = [:]
    @Published private(set) var customizationCurrentValues:
        [String: [String: NumericPreferenceCurrentValue]] = [:]
    @Published private(set) var customizationLoadRevisions: [String: Int] = [:]
    @Published private(set) var customizationInputErrors: [String: [String: LocalizedText]] = [:]
    @Published private(set) var contextValues: [PreferenceAddress: PreferenceValue] = [:]
    @Published private(set) var contextRestrictions: [String: LocalizedText] = [:]
    @Published private(set) var pendingCustomizationModes: [String: Bool] = [:]
    @Published private(set) var readStates: [String: PreferenceReadState] = [:]
    @Published private(set) var managementStates: [String: PreferenceManagementState] = [:]
    @Published var textDrafts: [String: String] = [:]
    @Published private(set) var busyItemIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isUndoing = false
    @Published private(set) var hasPendingPreferenceTransaction = false
    @Published private(set) var undoSummary: LocalizedText?
    @Published var alert: AppAlert?
    @Published var notice: AppNotice?

    private let executor: any PreferenceExecuting
    private let restarter: any ProcessRestarting
    private let managementProvider: any PreferenceManagementProviding
    private let powerExecutor: any PowerSettingsExecuting
    private let journal: any PreferenceTransactionJournaling
    private let timeProvider: any TimeProviding
    private let identifierProvider: any IdentifierProviding
    private let executorQueue = DispatchQueue(
        label: "com.codex.TerminalSettings.preferences",
        qos: .userInitiated
    )
    private let undoStorageURL: URL
    private let pendingTransactionURL: URL
    private let appDefaults: any ApplicationStateStoring
    private var undoRecord: UndoRecord?
    private var recoveryBaselines: [String: PreferenceRecoveryBaseline] = [:]
    private var pendingJournalIsUnreadable = false
    private var initializedCurrentDraftItemIDs: Set<String> = []
    private var finiteCustomizationDrafts: [String: [String: Double]] = [:]

    convenience init(
        appDefaults: UserDefaults = .standard,
        undoStorageURL: URL? = nil
    ) {
        let executor = PreferenceExecutor()
        self.init(
            executor: executor,
            restarter: executor,
            managementProvider: SystemPreferenceManagementProvider(),
            powerExecutor: PowerSettingsExecutor(),
            journal: FilePreferenceTransactionJournal(),
            appState: appDefaults,
            timeProvider: SystemTimeProvider(),
            identifierProvider: SystemIdentifierProvider(),
            undoStorageURL: undoStorageURL
        )
    }

    init(
        executor: any PreferenceExecuting,
        restarter: any ProcessRestarting,
        managementProvider: any PreferenceManagementProviding,
        powerExecutor: any PowerSettingsExecuting,
        journal: any PreferenceTransactionJournaling,
        appState: any ApplicationStateStoring,
        timeProvider: any TimeProviding,
        identifierProvider: any IdentifierProviding,
        undoStorageURL: URL? = nil
    ) {
        self.executor = executor
        self.restarter = restarter
        self.managementProvider = managementProvider
        self.powerExecutor = powerExecutor
        self.journal = journal
        self.timeProvider = timeProvider
        self.identifierProvider = identifierProvider
        self.appDefaults = appState
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let storageIdentifier = Bundle.main.bundleIdentifier ?? "com.codex.TerminalSettings"
        let defaultUndoStorageURL = applicationSupport
            .appendingPathComponent(storageIdentifier, isDirectory: true)
            .appendingPathComponent("last-undo.json", isDirectory: false)
        self.undoStorageURL = undoStorageURL ?? defaultUndoStorageURL
        self.pendingTransactionURL = (undoStorageURL ?? defaultUndoStorageURL)
            .deletingLastPathComponent()
            .appendingPathComponent("pending-preference-transaction.json", isDirectory: false)

        for item in PreferenceCatalog.items {
            readStates[item.id] = .loading
            managementStates[item.id] = item.requiresAdministrator ? .notApplicable : .checking
            loadCustomizationState(for: item)
            markCustomizationCurrentValues(for: item, as: .loading)
            loadRecoveryBaseline(for: item)
        }
        loadUndoRecord()
        loadPendingPreferenceTransaction()
    }

#if TERMINAL_SETTINGS_TESTING
    func prepareCustomizationModeTest(
        _ item: PreferenceItem,
        parentEnabled: Bool,
        currentValues: [PreferenceAddress: PreferenceValue] = [:]
    ) {
        readStates[item.id] = .enabled
        managementStates[item.id] = .unmanaged
        toggleValues[item.id] = parentEnabled
        loadCustomizationState(for: item)
        updateContextValues(for: item, using: currentValues)
        updateCustomizationCurrentValues(for: item, using: currentValues)
    }
#endif

    var configuredCount: Int {
        readStates.values.filter(\.isExplicitlyConfigured).count
    }

    var canUndo: Bool {
        guard !pendingJournalIsUnreadable else { return false }
        guard let undoRecord else { return false }
        let affectedAddresses = Set((undoRecord.before + undoRecord.after).map(\.address))
        return PreferenceCatalog.items
            .filter { !Set($0.allAddresses).isDisjoint(with: affectedAddresses) }
            .allSatisfy {
                !managementState(for: $0).isReadOnly && contextRestrictions[$0.id] == nil
            }
    }

    var isWorking: Bool {
        isRefreshing || isUndoing || !busyItemIDs.isEmpty
    }

    var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    func state(for item: PreferenceItem) -> PreferenceReadState {
        switch item.support() {
        case .unsupported(let message): return .unsupported(message)
        case .unverified(let message):
            if case .loading = readStates[item.id] ?? .loading {
                return .unverified(message)
            }
            return readStates[item.id] ?? .unverified(message)
        case .supported:
            return readStates[item.id] ?? .loading
        }
    }

    func managementState(for item: PreferenceItem) -> PreferenceManagementState {
        managementStates[item.id] ?? (item.requiresAdministrator ? .notApplicable : .checking)
    }

    func canRecover(_ item: PreferenceItem) -> Bool {
        guard canModify(item), item.supportsRecoveryAction else { return false }
        switch item.recovery.strategy {
        case .restoreBaseline:
            return item.recoveryPlan(baseline: recoveryBaselines[item.id]) != nil
        case .unavailable:
            return false
        case .deleteExplicit, .writePreset:
            return true
        }
    }

    func canDiscardRecoveryBaseline(_ item: PreferenceItem) -> Bool {
        guard !isWorking, !hasPendingPreferenceTransaction else { return false }
        guard case .restoreBaseline = item.recovery.strategy else { return false }
        return recoveryBaselines[item.id] != nil
    }

    func discardRecoveryBaseline(_ item: PreferenceItem) {
        guard canDiscardRecoveryBaseline(item) else { return }
        let persisted = commitRecoveryBaselines([:], itemIDs: [item.id])
        notice = makeNotice(
            message: persisted
                ? L("已放弃“\(item.title)”的旧接管记录；系统当前值未更改")
                : L("已放弃本次运行中的旧接管记录，但本地状态持久化未确认；系统当前值未更改"),
            canUndo: canUndo
        )
    }

    func canModify(_ item: PreferenceItem) -> Bool {
        guard !isWorking else { return false }
        guard !hasPendingPreferenceTransaction else { return false }
        guard !(managementStates[item.id] ?? .checking).isReadOnly else { return false }
        guard contextRestrictions[item.id] == nil else { return false }
        if case .unsupported = item.support() { return false }
        switch readStates[item.id] ?? .loading {
        case .loading, .unsupported, .error: return false
        default: break
        }
        return true
    }

    func refreshAll() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let items = PreferenceCatalog.items
        let readableItems = items.filter {
            if case .unsupported = $0.support() { return false }
            return true
        }
        let regularItems = readableItems.filter { !$0.requiresAdministrator }
        let privilegedItems = readableItems.filter(\.requiresAdministrator)
        for item in items {
            switch item.support() {
            case .unsupported(let message):
                readStates[item.id] = .unsupported(message)
                markCustomizationCurrentValues(for: item, as: .unavailable(message))
            default:
                readStates[item.id] = .loading
                markCustomizationCurrentValues(for: item, as: .loading)
            }
            managementStates[item.id] = item.requiresAdministrator ? .notApplicable : .checking
        }
        contextValues = [:]
        contextRestrictions = [:]
        let addresses = uniqueAddresses(regularItems.flatMap(\.readAddresses))
        let powerKeys = privilegedItems.compactMap(\.privilegedKey)
        let executor = self.executor
        let managementProvider = self.managementProvider
        let powerExecutor = self.powerExecutor
        executorQueue.async { [weak self] in
            let regularResult: Result<[PreferenceAddress: PreferenceValue], Error>
            do {
                regularResult = .success(try executor.readValues(for: addresses))
            } catch {
                regularResult = .failure(error)
            }
            let managementResult: Result<[String: Set<PreferenceAddress>], Error>
            do {
                managementResult = .success(try Dictionary(
                    uniqueKeysWithValues: regularItems.map { item in
                        (item.id, try managementProvider.forcedAddresses(
                            for: Array(Set(item.allAddresses + item.lockingContextAddresses))
                        ))
                    }
                ))
            } catch {
                managementResult = .failure(error)
            }
            let powerResult: Result<[PowerSettingSnapshot], Error>
            do {
                powerResult = .success(try powerExecutor.snapshots(for: powerKeys))
            } catch {
                powerResult = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                var errors: [LocalizedText] = []
                switch regularResult {
                case .success(let values):
                    for item in regularItems {
                        self.refresh(item, using: values)
                    }
                    switch managementResult {
                    case .success(let forcedAddressesByItem):
                        for item in regularItems {
                            let forced = forcedAddressesByItem[item.id] ?? []
                            if forced.isEmpty {
                                self.managementStates[item.id] = .unmanaged
                            } else if forced.count == item.allAddresses.count {
                                self.managementStates[item.id] = .forced(
                                    forced.sorted { $0.displayPath < $1.displayPath }
                                )
                            } else {
                                self.managementStates[item.id] = .partiallyForced(
                                    forced.sorted { $0.displayPath < $1.displayPath }
                                )
                            }
                            if !forced.isEmpty,
                               case .systemDefault = self.readStates[item.id] ?? .loading {
                                self.readStates[item.id] = .configured(L("由组织管理"))
                            }
                        }
                    case .failure(let error):
                        for item in regularItems {
                            self.managementStates[item.id] = .unknown(
                                error.displayMessage
                            )
                        }
                        errors.append(error.displayMessage)
                    }
                case .failure(let error):
                    for item in regularItems {
                        self.readStates[item.id] = .error(error.displayMessage)
                        self.managementStates[item.id] = .unknown(error.displayMessage)
                        self.markCustomizationCurrentValues(
                            for: item,
                            as: .unavailable(error.displayMessage)
                        )
                    }
                    errors.append(error.displayMessage)
                }

                switch powerResult {
                case .success(let snapshots):
                    let snapshotsByKey = Dictionary(
                        uniqueKeysWithValues: snapshots.map { ($0.key, $0) }
                    )
                    for item in privilegedItems {
                        guard let key = item.privilegedKey,
                              let snapshot = snapshotsByKey[key] else {
                            self.toggleValues[item.id] = false
                            self.readStates[item.id] = .unsupported(
                                L("此 Mac 的 pmset 配置不包含该能力")
                            )
                            continue
                        }
                        self.refreshPrivileged(item, using: snapshot)
                    }
                case .failure(let error):
                    for item in privilegedItems {
                        self.readStates[item.id] = .error(error.displayMessage)
                    }
                    errors.append(error.displayMessage)
                }

                if !errors.isEmpty {
                    self.alert = self.makeAlert(
                        title: L("无法读取系统偏好"),
                        message: errors.joined(separator: "\n\n")
                    )
                }
            }
        }
    }

    func isEnabled(_ item: PreferenceItem) -> Bool {
        toggleValues[item.id] ?? false
    }

    func selectedChoice(_ item: PreferenceItem) -> String {
        choiceValues[item.id] ?? "system"
    }

    func isCustomizationEnabled(_ item: PreferenceItem) -> Bool {
        pendingCustomizationModes[item.id] ?? customizationModes[item.id] ?? false
    }

    func customizationDraft(
        for item: PreferenceItem,
        parameter: NumericPreferenceParameter
    ) -> Double {
        customizationDrafts[item.id]?[parameter.id] ?? parameter.presetValue
    }

    func customizationCurrentValue(
        for item: PreferenceItem,
        parameter: NumericPreferenceParameter
    ) -> NumericPreferenceCurrentValue {
        customizationCurrentValues[item.id]?[parameter.id] ?? .loading
    }

    func customizationValidationError(_ item: PreferenceItem) -> LocalizedText? {
        item.numericConfiguration?.validationError(using: customizationDrafts[item.id] ?? [:])
    }

    func lastFiniteCustomizationDraft(
        for item: PreferenceItem,
        parameter: NumericPreferenceParameter
    ) -> Double {
        finiteCustomizationDrafts[item.id]?[parameter.id] ?? parameter.presetValue
    }

    func setCustomizationSpecialValue(
        _ item: PreferenceItem,
        parameter: NumericPreferenceParameter,
        value: Double?
    ) {
        guard canModify(item), isCustomizationEnabled(item),
              !parameter.specialValues.isEmpty else { return }
        if let value {
            guard parameter.specialValues.contains(where: { $0.value == value }) else { return }
        }
        setCustomizationDraft(
            item, parameter: parameter,
            value: value ?? lastFiniteCustomizationDraft(for: item, parameter: parameter)
        )
        clearCustomizationInputErrors(item)
        customizationLoadRevisions[item.id, default: 0] += 1
    }

    // A preset selection changes the draft, never the system preference.
    func applyCustomizationDraftPreset(
        _ item: PreferenceItem,
        parameter: NumericPreferenceParameter,
        value: Double
    ) {
        guard canModify(item), isCustomizationEnabled(item),
              parameter.presets.contains(where: { $0.value == value }) else { return }
        setCustomizationDraft(item, parameter: parameter, value: value)
        clearCustomizationInputErrors(item)
        customizationLoadRevisions[item.id, default: 0] += 1
    }

    func canLoadCurrentCustomizationValues(_ item: PreferenceItem) -> Bool {
        guard canModify(item), isCustomizationEnabled(item),
              let numeric = item.numericConfiguration,
              let currentValues = customizationCurrentValues[item.id] else {
            return false
        }
        return numeric.loadableDrafts(from: currentValues) != nil
    }

    func customizationLoadRevision(for item: PreferenceItem) -> Int {
        customizationLoadRevisions[item.id] ?? 0
    }

    func setCustomizationInputError(
        _ item: PreferenceItem,
        parameter: NumericPreferenceParameter,
        message: LocalizedText?
    ) {
        var errors = customizationInputErrors[item.id] ?? [:]
        guard errors[parameter.id] != message else { return }
        if let message {
            errors[parameter.id] = message
        } else {
            errors.removeValue(forKey: parameter.id)
        }
        if errors.isEmpty {
            customizationInputErrors.removeValue(forKey: item.id)
        } else {
            customizationInputErrors[item.id] = errors
        }
    }

    func clearCustomizationInputErrors(_ item: PreferenceItem) {
        guard customizationInputErrors[item.id] != nil else { return }
        customizationInputErrors.removeValue(forKey: item.id)
    }

    private func expectedCustomizationSnapshots(
        for item: PreferenceItem
    ) -> [PreferenceSnapshot]? {
        guard let numeric = item.numericConfiguration,
              let currentValues = customizationCurrentValues[item.id] else {
            return nil
        }
        return numeric.expectedSnapshots(from: currentValues)
    }

    func loadCurrentCustomizationValues(_ item: PreferenceItem) {
        guard canLoadCurrentCustomizationValues(item),
              let numeric = item.numericConfiguration,
              let currentValues = customizationCurrentValues[item.id],
              let loadedDrafts = numeric.loadableDrafts(from: currentValues) else {
            return
        }

        var drafts = customizationDrafts[item.id] ?? [:]
        for parameter in numeric.parameters {
            guard let value = loadedDrafts[parameter.id] else { return }
            let normalizedValue = parameter.normalized(value)
            drafts[parameter.id] = normalizedValue
        }
        customizationDrafts[item.id] = drafts
        persistCustomizationDrafts(drafts, for: item)
        rememberFiniteCustomizationDrafts(drafts, for: item)
        clearCustomizationInputErrors(item)
        customizationLoadRevisions[item.id, default: 0] += 1
        notice = makeNotice(
            message: L("已将最近一次刷新读取的“\(item.title)”系统当前值载入草稿；系统偏好未更改"),
            canUndo: canUndo
        )
    }

    func setCustomizationDraft(
        _ item: PreferenceItem,
        parameter: NumericPreferenceParameter,
        value: Double
    ) {
        guard item.numericConfiguration != nil else { return }
        let normalizedValue = parameter.normalized(value)
        var drafts = customizationDrafts[item.id] ?? [:]
        let currentValue = drafts[parameter.id] ?? parameter.presetValue
        guard currentValue != normalizedValue else { return }
        drafts[parameter.id] = normalizedValue
        customizationDrafts[item.id] = drafts
        persistCustomizationDrafts(drafts, for: item)
        rememberFiniteCustomizationDrafts(drafts, for: item)
    }

    func setCustomizationEnabled(_ item: PreferenceItem, enabled: Bool) {
        guard canModify(item), item.numericConfiguration != nil,
              enabled != isCustomizationEnabled(item) else { return }

        // This switch selects an editing mode only. Applying a system value is
        // always a separate, explicitly labelled button action.
        let title = enabled
            ? L("已开启“\(item.title)”的自定义编辑")
            : L("已关闭“\(item.title)”的自定义编辑")
        if !enabled {
            clearCustomizationInputErrors(item)
        }
        commitCustomizationModes([item.id: enabled])
        notice = makeNotice(
            message: title + L("；当前系统值未更改，系统设置撤销记录保持不变"),
            canUndo: canUndo
        )
    }

    func canApplyCustomization(_ item: PreferenceItem) -> Bool {
        guard canModify(item), item.numericConfiguration != nil,
              isCustomizationEnabled(item),
              customizationInputErrors[item.id]?.isEmpty != false,
              customizationValidationError(item) == nil,
              expectedCustomizationSnapshots(for: item) != nil else { return false }
        if case .toggle = item.control {
            return isEnabled(item)
        }
        return true
    }

    func applyCustomization(_ item: PreferenceItem) {
        guard canApplyCustomization(item),
              let expectedCurrent = expectedCustomizationSnapshots(for: item) else { return }
        applyChanges(
            title: L("已应用“\(item.title)”的自定义值"),
            itemIDs: [item.id],
            mutations: customizationMutations(for: item),
            restartProcesses: item.restartProcesses,
            recordUndo: true,
            expectedCurrent: expectedCurrent
        )
    }

    func canApplyCustomizationPreset(_ item: PreferenceItem) -> Bool {
        guard canModify(item), item.numericConfiguration != nil,
              !isCustomizationEnabled(item),
              item.numericConfiguration?.validationError(using: [:]) == nil,
              expectedCustomizationSnapshots(for: item) != nil else { return false }
        if case .toggle = item.control {
            return isEnabled(item)
        }
        return true
    }

    func applyCustomizationPreset(_ item: PreferenceItem) {
        guard canApplyCustomizationPreset(item),
              let expectedCurrent = expectedCustomizationSnapshots(for: item) else { return }
        let presetName = item.source.exposure == .systemSettingsEnhancement
            ? L("常用预设")
            : L("安全预设")
        applyChanges(
            title: L("已将“\(item.title)”应用为\(presetName)"),
            itemIDs: [item.id],
            mutations: customizationPresetMutations(for: item),
            restartProcesses: item.restartProcesses,
            recordUndo: true,
            expectedCurrent: expectedCurrent
        )
    }

    func setToggle(_ item: PreferenceItem, enabled: Bool) {
        guard canModify(item) else { return }
        switch item.control {
        case .toggle(let preference):
            let mutations: [PreferenceMutation]
            let expectedCurrent: [PreferenceSnapshot]
            if enabled, isCustomizationEnabled(item), item.numericConfiguration != nil {
                guard customizationInputErrors[item.id]?.isEmpty != false,
                      let snapshots = expectedCustomizationSnapshots(for: item) else {
                    return
                }
                mutations = customizationMutations(for: item)
                expectedCurrent = snapshots
            } else {
                mutations = enabled ? preference.enableMutations : preference.disableMutations
                expectedCurrent = []
            }
            let disabledTitle = preference.disableMutations.allSatisfy { $0.value == nil }
                ? L("已采用 Apple 默认“\(item.title)”")
                : L("已关闭“\(item.title)”")
            applyChanges(
                title: enabled ? L("已启用“\(item.title)”") : disabledTitle,
                itemIDs: [item.id],
                mutations: mutations,
                restartProcesses: item.restartProcesses,
                recordUndo: true,
                expectedCurrent: expectedCurrent
            )
        case .privilegedToggle(let preference):
            applyPrivilegedChange(item, preference: preference, enabled: enabled)
        case .choice, .text, .numeric:
            return
        }
    }

    func setChoice(_ item: PreferenceItem, optionID: String) {
        guard canModify(item),
              case .choice(let preference) = item.control,
              optionID != "custom",
              let option = preference.options.first(where: { $0.id == optionID }) else { return }
        let mutation = PreferenceMutation(address: preference.address, value: option.value)
        applyChanges(
            title: L("已将“\(item.title)”设为\(option.title)"),
            itemIDs: [item.id],
            mutations: [mutation],
            restartProcesses: item.restartProcesses,
            recordUndo: true,
            customizationChanges: item.numericConfiguration == nil ? [:] : [item.id: false]
        )
    }

    func applyText(_ item: PreferenceItem) {
        guard canModify(item), case .text(let preference) = item.control else { return }
        let draft = (textDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let mutation = PreferenceMutation(
            address: preference.address,
            value: draft.isEmpty ? nil : .string(draft)
        )
        applyChanges(
            title: draft.isEmpty ? L("已恢复“\(item.title)”") : L("已更新“\(item.title)”"),
            itemIDs: [item.id],
            mutations: [mutation],
            restartProcesses: item.restartProcesses,
            recordUndo: true
        )
    }

    func reset(_ item: PreferenceItem) {
        guard canModify(item), item.supportsRecoveryAction else { return }
        guard let plan = item.recoveryPlan(baseline: recoveryBaselines[item.id]) else {
            alert = makeAlert(
                title: L("没有可恢复的接管前值"),
                message: L("本应用尚未修改“\(item.title)”，因此没有可安全恢复的操作前快照。")
            )
            return
        }
        applyChanges(
            title: L("已为“\(item.title)”执行：\(item.recovery.actionTitle)"),
            itemIDs: [item.id],
            mutations: plan.mutations,
            restartProcesses: item.restartProcesses,
            recordUndo: true,
            customizationChanges: item.numericConfiguration == nil ? [:] : [item.id: false],
            expectedCurrent: plan.expectedCurrent,
            clearRecoveryBaselineItemIDs: plan.clearsBaseline ? [item.id] : []
        )
    }

    func resetCategory(_ category: SettingsCategory) {
        guard !isWorking, category != .advanced else { return }
        let items = PreferenceCatalog.items(in: category)
        guard items.allSatisfy({ canModify($0) }) else {
            alert = makeAlert(
                title: L("无法恢复本页"),
                message: L("本页包含尚未读取、读取失败或当前系统不支持的设置。请刷新状态后再试。")
            )
            return
        }
        var plans: [(PreferenceItem, PreferenceRecoveryPlan)] = []
        for item in items {
            if let plan = item.recoveryPlan(baseline: recoveryBaselines[item.id]) {
                plans.append((item, plan))
            } else if case .restoreBaseline = item.recovery.strategy {
                // The app has never taken control of this enhanced/mirrored
                // setting, so a category recovery must leave it untouched.
                continue
            } else {
                alert = makeAlert(
                    title: L("无法恢复本页"),
                    message: L("“\(item.title)”没有可安全执行的恢复策略。")
                )
                return
            }
        }
        let mutations = uniqueMutations(plans.flatMap { $0.1.mutations })
        guard !mutations.isEmpty else {
            notice = makeNotice(message: L("本页没有需要由本应用恢复的设置"), canUndo: canUndo)
            return
        }
        applyChanges(
            title: L("已按逐项策略恢复“\(category.title)”设置"),
            itemIDs: Set(plans.map { $0.0.id }),
            mutations: mutations,
            restartProcesses: Array(Set(plans.flatMap { $0.0.restartProcesses })),
            recordUndo: true,
            customizationChanges: Dictionary(uniqueKeysWithValues: plans.compactMap {
                $0.0.numericConfiguration == nil ? nil : ($0.0.id, false)
            }),
            expectedCurrent: plans.flatMap { $0.1.expectedCurrent },
            clearRecoveryBaselineItemIDs: Set(
                plans.filter { $0.1.clearsBaseline }.map { $0.0.id }
            )
        )
    }

    func undo() {
        guard !isWorking, canUndo, let record = undoRecord else { return }
        if let powerBefore = record.powerBefore,
           let powerAfter = record.powerAfter,
           !powerBefore.isEmpty {
            undoPowerChange(record, before: powerBefore, after: powerAfter)
            return
        }
        let itemIDs = Set(PreferenceCatalog.items.filter {
            !Set($0.allAddresses).isDisjoint(with: Set(record.before.map(\.address)))
        }.map(\.id))

        isUndoing = true
        busyItemIDs.formUnion(itemIDs)
        let executor = self.executor
        let restarter = self.restarter
        let managementProvider = self.managementProvider
        executorQueue.async { [self] in
            let result: Result<Void, Error>
            var beganRestore = false
            do {
                let addresses = Array(Set((record.before + record.after).map(\.address)))
                let affectedItems = PreferenceCatalog.items.filter { itemIDs.contains($0.id) }
                let managementAddresses = Array(Set(addresses + affectedItems.flatMap(\.lockingContextAddresses)))
                let forcedAddresses = try managementProvider.forcedAddresses(for: managementAddresses)
                guard forcedAddresses.isEmpty else {
                    throw PreferenceExecutorError.conflict(
                        L("相关偏好现已由组织管理，撤销未执行：") +
                            forcedAddresses.map(\.displayPath).sorted().joined(separator: "、")
                    )
                }
                try Self.ensureContextUnlocked(
                    items: PreferenceCatalog.items.filter { itemIDs.contains($0.id) },
                    executor: executor
                )
                try executor.ensureCurrentMatchesAny(
                    [record.before, record.after],
                    operation: L("撤销")
                )
                beganRestore = true
                try executor.restore(record.before)
                try executor.verify(record.before)
                restarter.restart(record.restartProcesses)
                result = .success(())
            } catch {
                let originalMessage = error.displayMessage
                var compensationMessage: LocalizedText = ""
                if beganRestore {
                    do {
                        let conflicts = try executor.restorePreservingExternalChanges(
                            record.after,
                            whenCurrentMatches: [record.before, record.after]
                        )
                        if !conflicts.isEmpty {
                            let paths = conflicts.map(\.displayPath).joined(separator: "、")
                            compensationMessage = L("\n撤销期间检测到外部新值，已保留而未覆盖：\(paths)")
                        }
                    } catch {
                        compensationMessage = L("\n恢复到撤销前状态也未完成：\(error.displayMessage)")
                    }
                }
                if beganRestore {
                    restarter.restart(record.restartProcesses)
                }
                result = .failure(PreferenceChangeFailure(
                    message: originalMessage + compensationMessage
                ))
            }

            DispatchQueue.main.async { [self] in
                self.isUndoing = false
                self.busyItemIDs.subtract(itemIDs)
                switch result {
                case .success:
                    if let modes = record.customizationBefore {
                        self.commitCustomizationModes(modes)
                    }
                    let recoveryPersisted: Bool
                    if let recoveryItemIDs = record.recoveryItemIDs {
                        recoveryPersisted = self.commitRecoveryBaselines(
                            record.recoveryBefore ?? [:],
                            itemIDs: Set(recoveryItemIDs)
                        )
                    } else {
                        recoveryPersisted = true
                    }
                    if !recoveryPersisted {
                        let journalPersisted = (try? self.journal.persist(
                            record,
                            to: self.pendingTransactionURL
                        )) != nil
                        self.hasPendingPreferenceTransaction = true
                        self.notice = self.makeNotice(
                            message: journalPersisted
                                ? L("系统值已恢复，但接管前基线未能持久化；恢复日志和撤销记录已保留，请重试撤销")
                                : L("系统值已恢复，但接管前基线和恢复日志均未能持久化；本次运行已锁定普通写入，请先重试撤销"),
                            canUndo: true
                        )
                    } else if self.clearPendingPreferenceTransaction() {
                        self.clearUndoRecord()
                        self.notice = self.makeNotice(message: L("已撤销上一次更改"), canUndo: false)
                    } else {
                        self.notice = self.makeNotice(
                            message: L("系统值已恢复，但写前恢复日志未能清理；可再次撤销以重试清理"),
                            canUndo: true
                        )
                    }
                    self.refreshAll()
                case .failure(let error):
                    self.alert = self.makeAlert(title: L("无法撤销"), message: error.displayMessage)
                }
            }
        }
    }

    private func undoPowerChange(
        _ record: UndoRecord,
        before: [PowerSettingSnapshot],
        after: [PowerSettingSnapshot]
    ) {
        let keys = Set(before.map(\.key))
        let itemIDs = Set<String>(PreferenceCatalog.items.compactMap { item -> String? in
            guard let key = item.privilegedKey, keys.contains(key) else { return nil }
            return item.id
        })

        isUndoing = true
        busyItemIDs.formUnion(itemIDs)
        let powerExecutor = self.powerExecutor
        executorQueue.async { [self] in
            let result: Result<Void, Error>
            do {
                try powerExecutor.ensureCurrentMatchesAny(
                    [before, after],
                    operation: L("撤销")
                )
                try powerExecutor.authorized { authorization in
                    var beganRestore = false
                    do {
                        // Authorization may keep the sheet open for an
                        // arbitrary time. Recheck after it completes so an
                        // external pmset change during that window is never
                        // overwritten by a stale snapshot.
                        try powerExecutor.ensureCurrentMatchesAny(
                            [before, after],
                            operation: L("撤销")
                        )
                        beganRestore = true
                        try powerExecutor.restore(before, authorization: authorization)
                        try powerExecutor.verify(before)
                    } catch {
                        let originalMessage = error.displayMessage
                        var compensationMessage: LocalizedText = ""
                        if beganRestore {
                            do {
                                let conflicts = try powerExecutor
                                    .restorePreservingExternalChanges(
                                        after,
                                        whenCurrentMatches: [before, after],
                                        authorization: authorization
                                    )
                                if !conflicts.isEmpty {
                                    compensationMessage = L("\n撤销期间检测到外部新值，") +
                                        L("已保留而未覆盖：") + conflicts.joined(separator: "、")
                                }
                            } catch {
                                compensationMessage = L("\n恢复到撤销前状态也未完成：") +
                                    error.displayMessage
                            }
                        }
                        throw PreferenceChangeFailure(
                            message: originalMessage + compensationMessage
                        )
                    }
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [self] in
                self.isUndoing = false
                self.busyItemIDs.subtract(itemIDs)
                switch result {
                case .success:
                    if self.clearPendingPreferenceTransaction() {
                        self.clearUndoRecord()
                        self.notice = self.makeNotice(
                            message: L("已撤销上一次高级更改"),
                            canUndo: false
                        )
                    } else {
                        self.notice = self.makeNotice(
                            message: L("高级系统值已恢复，但写前恢复日志未能清理；可再次撤销以重试清理"),
                            canUndo: true
                        )
                    }
                    self.refreshAll()
                case .failure(let error):
                    self.alert = self.makeAlert(
                        title: L("无法撤销高级设置"),
                        message: error.displayMessage
                    )
                }
            }
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func previewCommands(for item: PreferenceItem) -> [(LocalizedText, String)] {
        let recoveryCommands = recoveryPreviewCommands(for: item)
        switch item.control {
        case .toggle(let preference):
            let enable = preference.enableMutations.map(\.command).joined(separator: "\n")
            let disable = preference.disableMutations.map(\.command).joined(separator: "\n")
            var commands = [(
                item.numericConfiguration == nil ? L("启用") : L("安全预设"),
                enable
            )]
            if item.numericConfiguration != nil {
                commands.append((
                    L("自定义（当前滑块值）"),
                    customizationMutations(for: item).map(\.command).joined(separator: "\n")
                ))
            }
            commands.append((
                preference.disableMutations.allSatisfy { $0.value == nil }
                    ? L("关闭（删除用户显式值）")
                    : L("关闭"),
                disable
            ))
            if case .restoreBaseline = item.recovery.strategy {
                commands.append(contentsOf: recoveryCommands)
            }
            return commands
        case .choice(let preference):
            var commands = preference.options.compactMap { option -> (LocalizedText, String)? in
                guard let value = option.value else { return nil }
                let mutation = PreferenceMutation(address: preference.address, value: value)
                return (option.title, mutation.command)
            }
            if item.numericConfiguration != nil {
                commands.append((
                    L("自定义（当前滑块值）"),
                    customizationMutations(for: item).map(\.command).joined(separator: "\n")
                ))
            }
            commands.append(contentsOf: recoveryCommands)
            return commands
        case .text(let preference):
            let draft = (textDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var commands: [(LocalizedText, String)] = []
            if !draft.isEmpty {
                commands.append((L("应用当前文字"), PreferenceMutation(
                    address: preference.address,
                    value: .string(draft)
                ).command))
            }
            commands.append(contentsOf: recoveryCommands)
            return commands
        case .numeric:
            var commands = [(
                L("常用预设"),
                customizationPresetMutations(for: item).map(\.command).joined(separator: "\n")
            )]
            commands.append((
                L("自定义（当前数值）"),
                customizationMutations(for: item).map(\.command).joined(separator: "\n")
            ))
            commands.append(contentsOf: recoveryCommands)
            return commands
        case .privilegedToggle(let preference):
            return [
                (L("开启（需要管理员权限）"), preference.command(enabled: true)),
                (L("关闭（需要管理员权限）"), preference.command(enabled: false))
            ]
        }
    }

    private func recoveryPreviewCommands(for item: PreferenceItem) -> [(LocalizedText, String)] {
        guard let plan = item.recoveryPlan(baseline: recoveryBaselines[item.id]) else {
            return []
        }
        let command = plan.mutations.map(\.command).joined(separator: "\n")
        guard !command.isEmpty else { return [] }
        return [(item.recovery.actionTitle, command)]
    }

    func copyCommand(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        notice = makeNotice(message: L("命令已复制"), canUndo: undoRecord != nil)
    }

    private func markCustomizationCurrentValues(
        for item: PreferenceItem,
        as state: NumericPreferenceCurrentValue
    ) {
        guard let numeric = item.numericConfiguration else { return }
        customizationCurrentValues[item.id] = Dictionary(
            uniqueKeysWithValues: numeric.parameters.map { ($0.id, state) }
        )
    }

    private func updateCustomizationCurrentValues(
        for item: PreferenceItem,
        using values: [PreferenceAddress: PreferenceValue]
    ) {
        guard let numeric = item.numericConfiguration else { return }
        let current = numeric.currentValues(using: values)
        customizationCurrentValues[item.id] = current
        if numeric.initializesDraftsFromCurrentValue,
           !initializedCurrentDraftItemIDs.contains(item.id),
           let drafts = numeric.loadableDrafts(from: current) {
            customizationDrafts[item.id] = drafts
            initializedCurrentDraftItemIDs.insert(item.id)
            for parameter in numeric.parameters where !parameter.specialValues.isEmpty {
                if let value = drafts[parameter.id], parameter.range.contains(value) {
                    finiteCustomizationDrafts[item.id, default: [:]][parameter.id] = value
                }
            }
        }
    }

    private func updateContextValues(
        for item: PreferenceItem,
        using values: [PreferenceAddress: PreferenceValue]
    ) {
        for address in item.contextAddresses {
            contextValues[address] = values[address]
        }
        contextRestrictions[item.id] = Self.contextRestriction(for: item, using: values)
    }

    nonisolated private static func contextRestriction(
        for item: PreferenceItem,
        using values: [PreferenceAddress: PreferenceValue]
    ) -> LocalizedText? {
        for address in item.lockingContextAddresses {
            guard let value = values[address] else { continue }
            switch value {
            case .bool(false), .integer(0): break
            case .bool(true), .integer(1):
                return L("系统已锁定尺寸控制（\(address.key)），此尺寸组保持只读")
            default:
                return L("无法确认尺寸锁定状态（\(address.key)），此尺寸组保持只读")
            }
        }
        return nil
    }

    nonisolated private static func ensureContextUnlocked(
        items: [PreferenceItem],
        executor: any PreferenceExecuting
    ) throws {
        let addresses = Array(Set(items.flatMap(\.lockingContextAddresses)))
        guard !addresses.isEmpty else { return }
        let values = try executor.readValues(for: addresses)
        for item in items {
            if let reason = contextRestriction(for: item, using: values) {
                throw PreferenceExecutorError.conflict(reason)
            }
        }
    }

    private func refresh(
        _ item: PreferenceItem,
        using values: [PreferenceAddress: PreferenceValue]
    ) {
        updateContextValues(for: item, using: values)
        if let numeric = item.numericConfiguration {
            updateCustomizationCurrentValues(for: item, using: values)
            let invalidDescriptions = numeric.parameters.compactMap { parameter -> LocalizedText? in
                guard let state = customizationCurrentValues[item.id]?[parameter.id],
                      case .invalid(let rawValue) = state else {
                    return nil
                }
                return L("\(parameter.title)当前值 \(rawValue) 的类型、范围或分度不在安全编辑边界内")
            }
            if !invalidDescriptions.isEmpty {
                readStates[item.id] = .error(invalidDescriptions.joined(separator: L("；")))
                return
            }
        }

        switch item.control {
        case .toggle(let preference):
            if item.numericConfiguration != nil {
                let expectedMutations = customizationMutations(for: item)
                let explicitValues = expectedMutations.compactMap { values[$0.address] }
                guard !explicitValues.isEmpty else {
                    toggleValues[item.id] = false
                    readStates[item.id] = .systemDefault
                    return
                }
                let fullyConfigured = explicitValues.count == expectedMutations.count
                toggleValues[item.id] = fullyConfigured
                if fullyConfigured {
                    let matchesDraft = expectedMutations.allSatisfy { mutation in
                        guard let expected = mutation.value,
                              let stored = values[mutation.address] else { return false }
                        return expected.matches(stored)
                    }
                    let matchesPreset = preference.enableMutations.allSatisfy { mutation in
                        guard let expected = mutation.value,
                              let stored = values[mutation.address] else { return false }
                        return expected.matches(stored)
                    }
                    if !isCustomizationEnabled(item), matchesPreset {
                        readStates[item.id] = .enabled
                    } else {
                        readStates[item.id] = .configured(
                            matchesDraft ? L("自定义值") : L("其他自定义值")
                        )
                    }
                } else {
                    readStates[item.id] = .configured(L("部分设置"))
                }
                return
            }
            let explicitValues = preference.enableMutations.compactMap { mutation in
                values[mutation.address]
            }
            guard !explicitValues.isEmpty else {
                toggleValues[item.id] = false
                readStates[item.id] = .systemDefault
                return
            }
            let enabled = preference.enableMutations.allSatisfy { mutation in
                guard let expected = mutation.value,
                      let stored = values[mutation.address] else { return false }
                return expected.matches(stored)
            }
            let explicitlyDisabled = !preference.disableMutations.isEmpty &&
                preference.disableMutations.allSatisfy { mutation in
                    guard let expected = mutation.value,
                          let stored = values[mutation.address] else { return false }
                    return expected.matches(stored)
                }
            toggleValues[item.id] = enabled
            if enabled {
                readStates[item.id] = .enabled
            } else if explicitlyDisabled {
                readStates[item.id] = .disabled
            } else if explicitValues.count < preference.enableMutations.count {
                readStates[item.id] = .configured(L("部分设置"))
            } else {
                readStates[item.id] = .configured(L("自定义值"))
            }
        case .choice(let preference):
            guard let stored = values[preference.address] else {
                choiceValues[item.id] = "system"
                customChoiceValues[item.id] = nil
                readStates[item.id] = .systemDefault
                return
            }
            if let option = preference.options.first(where: {
                guard let value = $0.value else { return false }
                return value.matches(stored)
            }) {
                choiceValues[item.id] = option.id
                customChoiceValues[item.id] = nil
                readStates[item.id] = .configured(option.title)
            } else {
                choiceValues[item.id] = "custom"
                customChoiceValues[item.id] = stored.displayValue
                readStates[item.id] = .configured(LocalizedText(verbatim: stored.displayValue))
            }
        case .text(let preference):
            guard let raw = values[preference.address]?.displayValue else {
                textDrafts[item.id] = ""
                readStates[item.id] = .systemDefault
                return
            }
            textDrafts[item.id] = raw
            readStates[item.id] = .configured("")
        case .numeric(let preference):
            var storedPairs: [(NumericPreferenceParameter, Double)] = []
            for parameter in preference.parameters {
                guard let storedValue = values[parameter.address] else { continue }
                guard let displayedValue = parameter.displayedValue(from: storedValue) else {
                    readStates[item.id] = .error(
                        L("\(parameter.title)当前值 \(storedValue.displayValue) 的类型、范围或分度不在安全编辑边界内")
                    )
                    return
                }
                storedPairs.append((parameter, displayedValue))
            }
            guard !storedPairs.isEmpty else {
                readStates[item.id] = .systemDefault
                return
            }
            guard storedPairs.count == preference.parameters.count else {
                readStates[item.id] = .configured(L("部分设置"))
                return
            }
            let summary = storedPairs.map {
                L("\($0.0.title) \($0.0.displayValue($0.1))")
            }.joined(separator: L("；"))
            readStates[item.id] = .configured(summary)
        case .privilegedToggle:
            return
        }
    }

    private func refreshPrivileged(
        _ item: PreferenceItem,
        using snapshot: PowerSettingSnapshot
    ) {
        let values = snapshot.values.map(\.value)
        guard !values.isEmpty, values.allSatisfy({ [0, 1].contains($0) }) else {
            toggleValues[item.id] = false
            readStates[item.id] = .error(L("pmset 返回了非布尔值"))
            return
        }
        if values.allSatisfy({ $0 == 1 }) {
            toggleValues[item.id] = true
            readStates[item.id] = .enabled
        } else if values.allSatisfy({ $0 == 0 }) {
            toggleValues[item.id] = false
            readStates[item.id] = .disabled
        } else {
            toggleValues[item.id] = false
            readStates[item.id] = .configured(L("不同电源来源状态不一致"))
        }
    }

    private func applyPrivilegedChange(
        _ item: PreferenceItem,
        preference: PrivilegedTogglePreference,
        enabled: Bool
    ) {
        let title = enabled ? L("已启用“\(item.title)”") : L("已关闭“\(item.title)”")
        let fallbackTitle = titleForNewRecord(title)
        busyItemIDs.insert(item.id)
        hasPendingPreferenceTransaction = true
        let powerExecutor = self.powerExecutor
        let pendingTransactionURL = self.pendingTransactionURL

        executorQueue.async { [self] in
            var beganWrite = false
            var retainPendingJournal = false
            let result: Result<UndoRecord, Error>
            do {
                guard let before = try powerExecutor.snapshot(for: preference.key) else {
                    throw PowerSettingsError.unsupported(preference.key)
                }
                guard before.values.allSatisfy({ [0, 1].contains($0.value) }) else {
                    throw PowerSettingsError.verification(
                        L("\(preference.key) 当前不是受支持的 0/1 布尔状态")
                    )
                }
                let intended = PowerSettingSnapshot(
                    key: preference.key,
                    values: before.values.map {
                        PowerSourceValue(source: $0.source, value: enabled ? 1 : 0)
                    }
                )
                let record = UndoRecord(
                    title: fallbackTitle,
                    displayAction: title,
                    before: [],
                    after: [],
                    restartProcesses: [],
                    createdAt: timeProvider.now(),
                    powerBefore: [before],
                    powerAfter: [intended]
                )
                guard PersistedRecordPolicy.isAllowed(record) else {
                    throw PreferenceExecutorError.verification(
                        L("高级写前恢复记录不符合当前目录白名单")
                    )
                }

                // `pmset` writes each available power source separately. Save
                // the complete before/after pair before the first privileged
                // mutation so a process exit cannot strand a partial state
                // without a recovery path.
                try journal.persist(record, to: pendingTransactionURL)
                retainPendingJournal = true

                try powerExecutor.authorized { authorization in
                    do {
                        // The administrator sheet creates a time-of-check /
                        // time-of-use window. Verify the saved baseline again
                        // after authorization and immediately before writing.
                        try powerExecutor.ensureUnchanged(since: [before])
                        beganWrite = true
                        try powerExecutor.apply(intended, authorization: authorization)
                        try powerExecutor.verify([intended])
                    } catch {
                        let originalMessage = error.displayMessage
                        let helperOutcomeIsUnknown: Bool
                        if case PowerSettingsError.privilegedTimeout = error {
                            helperOutcomeIsUnknown = true
                        } else {
                            helperOutcomeIsUnknown = false
                        }
                        var rollbackMessage: LocalizedText = ""
                        if beganWrite {
                            do {
                                let conflicts = try powerExecutor
                                    .restorePreservingExternalChanges(
                                        [before],
                                        whenCurrentMatches: [[before], [intended]],
                                        authorization: authorization
                                    )
                                if !conflicts.isEmpty {
                                    rollbackMessage = L("\n回滚期间检测到外部新值，已保留而未覆盖：") +
                                        conflicts.joined(separator: "、")
                                } else {
                                    try powerExecutor.verify([before])
                                    retainPendingJournal = helperOutcomeIsUnknown
                                    if helperOutcomeIsUnknown {
                                        rollbackMessage += L("\n旧授权 helper 的最终退出状态未知；写前恢复日志将保留并锁定后续写入。")
                                    }
                                }
                            } catch {
                                rollbackMessage = L("\n自动回滚也未能完成：\(error.displayMessage)")
                                retainPendingJournal = true
                            }
                        }
                        throw PreferenceChangeFailure(
                            message: originalMessage + rollbackMessage,
                            helperOutcomeIsUnknown: helperOutcomeIsUnknown
                        )
                    }
                }

                result = .success(record)
            } catch {
                let helperOutcomeIsUnknown: Bool
                if case PowerSettingsError.privilegedTimeout = error {
                    helperOutcomeIsUnknown = true
                } else if let changeFailure = error as? PreferenceChangeFailure,
                          changeFailure.helperOutcomeIsUnknown {
                    helperOutcomeIsUnknown = true
                } else {
                    helperOutcomeIsUnknown = false
                }
                if !beganWrite && !helperOutcomeIsUnknown {
                    retainPendingJournal = false
                }
                if !retainPendingJournal {
                    journal.remove(at: pendingTransactionURL)
                }
                result = .failure(error)
            }

            DispatchQueue.main.async { [self] in
                self.busyItemIDs.remove(item.id)
                switch result {
                case .success(let record):
                    let persisted = self.setUndoRecord(record)
                    let journalCleared = persisted
                        ? self.clearPendingPreferenceTransaction()
                        : false
                    if !persisted || !journalCleared {
                        self.hasPendingPreferenceTransaction = true
                    }
                    let suffix = persisted && journalCleared
                        ? ""
                        : L("（写前恢复日志已保留；请先撤销后再继续修改）")
                    self.notice = self.makeNotice(message: title + suffix, canUndo: true)
                case .failure(let error):
                    let recoveryAvailable: Bool
                    if retainPendingJournal {
                        self.loadPendingPreferenceTransaction(required: true)
                        recoveryAvailable = self.hasPendingPreferenceTransaction
                    } else if self.clearPendingPreferenceTransaction() {
                        recoveryAvailable = false
                    } else {
                        self.loadPendingPreferenceTransaction(required: true)
                        recoveryAvailable = self.hasPendingPreferenceTransaction
                    }
                    let recoveryMessage = recoveryAvailable
                        ? L("\n\n写前恢复日志已保留。请使用工具栏“撤销上次更改”安全恢复后再继续。")
                        : ""
                    self.alert = self.makeAlert(
                        title: L("高级设置未完成"),
                        message: error.displayMessage + recoveryMessage
                    )
                }
                self.refreshAll()
            }
        }
    }

    private func applyChanges(
        title: LocalizedText,
        itemIDs: Set<String>,
        mutations: [PreferenceMutation],
        restartProcesses: [String],
        recordUndo: Bool,
        customizationChanges: [String: Bool] = [:],
        expectedCurrent: [PreferenceSnapshot] = [],
        clearRecoveryBaselineItemIDs: Set<String> = []
    ) {
        let fallbackTitle = titleForNewRecord(title)
        let customizationBefore: [String: Bool]? = customizationChanges.isEmpty
            ? nil
            : Dictionary(uniqueKeysWithValues: customizationChanges.keys.map {
                ($0, customizationModes[$0] ?? false)
            })
        let customizationAfter: [String: Bool]? = customizationChanges.isEmpty
            ? nil
            : customizationChanges
        if !customizationChanges.isEmpty {
            pendingCustomizationModes.merge(customizationChanges) { _, new in new }
        }
        let addresses = uniqueAddresses(mutations.map(\.address))
        var intendedByAddress: [PreferenceAddress: PreferenceValue?] = [:]
        for mutation in mutations {
            intendedByAddress[mutation.address] = mutation.value
        }
        let intended = addresses.map {
            PreferenceSnapshot(address: $0, value: intendedByAddress[$0] ?? nil)
        }
        let recoveryItems = PreferenceCatalog.items.filter { item in
            guard itemIDs.contains(item.id) else { return false }
            if case .restoreBaseline = item.recovery.strategy { return true }
            return false
        }
        let captureRecoveryBaselineItemIDs = Set(recoveryItems.map(\.id))
            .subtracting(clearRecoveryBaselineItemIDs)
        let affectedRecoveryItemIDs = captureRecoveryBaselineItemIDs
            .union(clearRecoveryBaselineItemIDs)
        let recoveryBefore = Dictionary(uniqueKeysWithValues:
            affectedRecoveryItemIDs.compactMap { itemID in
                recoveryBaselines[itemID].map { (itemID, $0) }
            }
        )
        var guardedExpectedByAddress: [PreferenceAddress: PreferenceSnapshot] = [:]
        for item in recoveryItems {
            for snapshot in recoveryBaselines[item.id]?.lastApplied ?? [] {
                guardedExpectedByAddress[snapshot.address] = snapshot
            }
        }
        for snapshot in expectedCurrent {
            guardedExpectedByAddress[snapshot.address] = snapshot
        }
        let guardedExpected = Array(guardedExpectedByAddress.values)
        busyItemIDs.formUnion(itemIDs)
        hasPendingPreferenceTransaction = true
        let executor = self.executor
        let restarter = self.restarter
        let managementProvider = self.managementProvider
        let pendingTransactionURL = self.pendingTransactionURL
        executorQueue.async { [self] in
            var before: [PreferenceSnapshot] = []
            var beganWrite = false
            var retainPendingJournal = false
            let result: Result<UndoRecord, Error>
            do {
                before = try executor.snapshots(for: addresses)
                let affectedItems = PreferenceCatalog.items.filter { itemIDs.contains($0.id) }
                let managementAddresses = Array(Set(addresses + affectedItems.flatMap(\.lockingContextAddresses)))
                let forcedAddresses = try managementProvider.forcedAddresses(for: managementAddresses)
                guard forcedAddresses.isEmpty else {
                    throw PreferenceExecutorError.conflict(
                        L("相关偏好现已由组织管理，本次操作未执行：") +
                            forcedAddresses.map(\.displayPath).sorted().joined(separator: "、")
                    )
                }
                try Self.ensureContextUnlocked(
                    items: PreferenceCatalog.items.filter { itemIDs.contains($0.id) },
                    executor: executor
                )
                if !guardedExpected.isEmpty {
                    try executor.ensureUnchanged(since: guardedExpected)
                }

                var preparedRecoveryAfter = recoveryBefore
                for itemID in clearRecoveryBaselineItemIDs {
                    preparedRecoveryAfter[itemID] = nil
                }
                for item in recoveryItems
                    where captureRecoveryBaselineItemIDs.contains(item.id) {
                    let itemAddresses = Set(item.allAddresses)
                    let beforeForItem = before.filter { itemAddresses.contains($0.address) }
                    let intendedForItem = intended.filter { itemAddresses.contains($0.address) }
                    guard beforeForItem.count == itemAddresses.count,
                          intendedForItem.count == itemAddresses.count,
                          Set(beforeForItem.map(\.address)) == itemAddresses,
                          Set(intendedForItem.map(\.address)) == itemAddresses else {
                        throw PreferenceExecutorError.verification(
                            L("未能为“\(item.title)”建立完整的写前恢复快照")
                        )
                    }
                    preparedRecoveryAfter[item.id] = PreferenceRecoveryBaseline(
                        itemID: item.id,
                        before: recoveryBefore[item.id]?.before ?? beforeForItem,
                        lastApplied: intendedForItem,
                        createdAt: recoveryBefore[item.id]?.createdAt ?? timeProvider.now()
                    )
                }
                let preparedRecord = UndoRecord(
                    title: fallbackTitle,
                    displayAction: title,
                    before: before,
                    after: intended,
                    restartProcesses: restartProcesses,
                    createdAt: timeProvider.now(),
                    customizationBefore: customizationBefore,
                    customizationAfter: customizationAfter,
                    recoveryItemIDs: affectedRecoveryItemIDs.isEmpty
                        ? nil
                        : affectedRecoveryItemIDs.sorted(),
                    recoveryBefore: affectedRecoveryItemIDs.isEmpty ? nil : recoveryBefore,
                    recoveryAfter: affectedRecoveryItemIDs.isEmpty
                        ? nil
                        : preparedRecoveryAfter
                )
                guard PersistedRecordPolicy.isAllowed(preparedRecord) else {
                    throw PreferenceExecutorError.verification(
                        L("写前恢复记录不符合当前目录白名单")
                    )
                }
                try journal.persist(
                    preparedRecord,
                    to: pendingTransactionURL
                )
                retainPendingJournal = true

                for mutation in mutations {
                    beganWrite = true
                    try executor.apply(mutation)
                }

                try executor.verify(intended)
                restarter.restart(restartProcesses)
                let after = try executor.snapshots(for: addresses)
                var recoveryAfter = preparedRecoveryAfter
                for item in recoveryItems where captureRecoveryBaselineItemIDs.contains(item.id) {
                    let itemAddresses = Set(item.allAddresses)
                    let afterForItem = after.filter { itemAddresses.contains($0.address) }
                    guard afterForItem.count == itemAddresses.count,
                          Set(afterForItem.map(\.address)) == itemAddresses,
                          let preparedBaseline = preparedRecoveryAfter[item.id] else {
                        throw PreferenceExecutorError.verification(
                            L("未能为“\(item.title)”建立完整的接管前快照")
                        )
                    }
                    recoveryAfter[item.id] = PreferenceRecoveryBaseline(
                        itemID: item.id,
                        before: preparedBaseline.before,
                        lastApplied: afterForItem,
                        createdAt: preparedBaseline.createdAt
                    )
                }
                let completedRecord = UndoRecord(
                    title: fallbackTitle,
                    displayAction: title,
                    before: before,
                    after: after,
                    restartProcesses: restartProcesses,
                    createdAt: timeProvider.now(),
                    customizationBefore: customizationBefore,
                    customizationAfter: customizationAfter,
                    recoveryItemIDs: affectedRecoveryItemIDs.isEmpty
                        ? nil
                        : affectedRecoveryItemIDs.sorted(),
                    recoveryBefore: affectedRecoveryItemIDs.isEmpty ? nil : recoveryBefore,
                    recoveryAfter: affectedRecoveryItemIDs.isEmpty ? nil : recoveryAfter
                )
                guard PersistedRecordPolicy.isAllowed(completedRecord) else {
                    throw PreferenceExecutorError.verification(
                        L("写后恢复记录不符合当前目录白名单")
                    )
                }
                // Refresh the durable journal with the exact values read back
                // from the system before publishing success to the UI.
                try journal.persist(
                    completedRecord,
                    to: pendingTransactionURL
                )
                result = .success(completedRecord)
            } catch {
                let originalMessage = error.displayMessage
                var rollbackMessage: LocalizedText = ""
                if beganWrite, !before.isEmpty {
                    do {
                        try executor.ensureCurrentMatchesAny(
                            [before, intended],
                            operation: L("自动回滚")
                        )
                        try executor.restore(before)
                        try executor.verify(before)
                        retainPendingJournal = false
                    } catch {
                        rollbackMessage = L("\n自动回滚也未能完成：\(error.displayMessage)")
                        retainPendingJournal = true
                    }
                } else {
                    retainPendingJournal = false
                }
                if beganWrite {
                    restarter.restart(restartProcesses)
                }
                if !retainPendingJournal {
                    journal.remove(at: pendingTransactionURL)
                }
                result = .failure(PreferenceChangeFailure(
                    message: originalMessage + rollbackMessage
                ))
            }

            DispatchQueue.main.async { [self] in
                self.busyItemIDs.subtract(itemIDs)
                switch result {
                case .success(let record):
                    if let modes = record.customizationAfter {
                        self.commitCustomizationModes(modes)
                    }
                    for itemID in customizationChanges.keys {
                        self.pendingCustomizationModes[itemID] = nil
                    }
                    let recoveryPersisted: Bool
                    if let recoveryItemIDs = record.recoveryItemIDs {
                        recoveryPersisted = self.commitRecoveryBaselines(
                            record.recoveryAfter ?? [:],
                            itemIDs: Set(recoveryItemIDs)
                        )
                    } else {
                        recoveryPersisted = true
                    }
                    var persisted = true
                    if recordUndo {
                        persisted = self.setUndoRecord(record)
                    }
                    let journalCleared: Bool
                    if persisted && recoveryPersisted {
                        journalCleared = self.clearPendingPreferenceTransaction()
                    } else {
                        journalCleared = false
                        self.hasPendingPreferenceTransaction = true
                    }
                    let suffix = persisted && recoveryPersisted && journalCleared
                        ? ""
                        : L("（写前恢复日志已保留；请先撤销后再继续修改）")
                    self.notice = self.makeNotice(message: title + suffix, canUndo: self.canUndo)
                    self.refreshAll()
                case .failure(let error):
                    for itemID in customizationChanges.keys {
                        self.pendingCustomizationModes[itemID] = nil
                    }
                    let recoveryAvailable: Bool
                    if retainPendingJournal {
                        self.loadPendingPreferenceTransaction(required: true)
                        recoveryAvailable = self.hasPendingPreferenceTransaction
                    } else if self.clearPendingPreferenceTransaction() {
                        recoveryAvailable = false
                    } else {
                        self.loadPendingPreferenceTransaction(required: true)
                        recoveryAvailable = self.hasPendingPreferenceTransaction
                    }
                    let recoveryMessage = recoveryAvailable
                        ? L("\n\n写前恢复日志已保留。请使用工具栏“撤销上次更改”安全恢复后再继续。")
                        : ""
                    self.alert = self.makeAlert(
                        title: L("设置未完成"),
                        message: error.displayMessage + recoveryMessage
                    )
                    self.refreshAll()
                }
            }
        }
    }

    @discardableResult
    private func setUndoRecord(_ record: UndoRecord) -> Bool {
        guard PersistedRecordPolicy.isAllowed(record) else { return false }
        undoRecord = record
        undoSummary = L("可撤销：\(record.localizedTitle())")
        let envelope = PersistedUndoEnvelope(schemaVersion: 4, record: record)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            try FileManager.default.createDirectory(
                at: undoStorageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: undoStorageURL, options: .atomic)
            return true
        } catch {
            // Never leave an older, unrelated record looking current after a
            // failed persistence attempt.
            try? FileManager.default.removeItem(at: undoStorageURL)
            return false
        }
    }

    private func loadUndoRecord() {
        guard let data = try? Data(contentsOf: undoStorageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(PersistedUndoEnvelope.self, from: data),
              [1, 2, 3, 4].contains(envelope.schemaVersion),
              PersistedRecordPolicy.isAllowed(envelope.record) else {
            try? FileManager.default.removeItem(at: undoStorageURL)
            return
        }
        undoRecord = envelope.record
        undoSummary = L("可撤销：\(envelope.record.localizedTitle())")
    }

    private func loadPendingPreferenceTransaction(required: Bool = false) {
        do {
            guard let record = try journal.read(from: pendingTransactionURL) else {
                pendingJournalIsUnreadable = required
                hasPendingPreferenceTransaction = required
                if required {
                    undoRecord = nil
                    undoSummary = nil
                    alert = makeAlert(
                        title: L("写前恢复日志意外缺失"),
                        message: L("事务已进入需要恢复的状态，但恢复日志当前不可用。为避免覆盖未知状态，普通与高级写入继续锁定。")
                    )
                }
                return
            }
            guard PersistedRecordPolicy.isAllowed(record) else {
                throw PreferenceExecutorError.verification(
                    L("写前恢复日志包含目录之外的地址、能力或进程")
                )
            }
            pendingJournalIsUnreadable = false
            undoRecord = record
            undoSummary = L("检测到未完成操作，可恢复：\(record.localizedTitle())")
            hasPendingPreferenceTransaction = true
            alert = makeAlert(
                title: L("检测到未完成的设置事务"),
                message: L("上次操作可能在普通偏好多键写入或高级电源来源写入期间中断。为避免覆盖未知状态，设置修改已暂时锁定；请先使用工具栏“撤销上次更改”按写前快照恢复。")
            )
        } catch {
            // A journal that exists but cannot be validated may describe a
            // partially completed transaction. Keep the original evidence in
            // place and fail closed across launches instead of reopening writes.
            pendingJournalIsUnreadable = true
            hasPendingPreferenceTransaction = true
            undoRecord = nil
            undoSummary = nil
            alert = makeAlert(
                title: L("写前恢复日志无法读取"),
                message: L("为避免覆盖可能只完成一部分的设置，普通与高级写入已锁定。原日志保留在：\(pendingTransactionURL.path)\n\n\(error.displayMessage)")
            )
        }
    }

    @discardableResult
    private func clearPendingPreferenceTransaction() -> Bool {
        let cleared = journal.remove(at: pendingTransactionURL)
        if cleared {
            pendingJournalIsUnreadable = false
        }
        hasPendingPreferenceTransaction = !cleared
        return cleared
    }

    private func makeAlert(title: LocalizedText, message: LocalizedText) -> AppAlert {
        AppAlert(
            id: identifierProvider.makeIdentifier(),
            title: title,
            message: message
        )
    }

    private func titleForNewRecord(_ title: LocalizedText) -> String {
        let choice = AppLanguage(rawValue: appDefaults.object(forKey: AppLanguageStore.preferenceKey) as? String ?? "") ?? .system
        return title.rendered(language: choice.resolved())
    }

    private func makeNotice(message: LocalizedText, canUndo: Bool) -> AppNotice {
        AppNotice(
            id: identifierProvider.makeIdentifier(),
            message: message,
            canUndo: canUndo
        )
    }

    private func clearUndoRecord() {
        undoRecord = nil
        undoSummary = nil
        try? FileManager.default.removeItem(at: undoStorageURL)
    }

    private func uniqueAddresses(_ addresses: [PreferenceAddress]) -> [PreferenceAddress] {
        var seen = Set<PreferenceAddress>()
        return addresses.filter { seen.insert($0).inserted }
    }

    private func uniqueMutations(_ mutations: [PreferenceMutation]) -> [PreferenceMutation] {
        var latest: [PreferenceAddress: PreferenceMutation] = [:]
        var order: [PreferenceAddress] = []
        for mutation in mutations {
            if latest[mutation.address] == nil {
                order.append(mutation.address)
            }
            latest[mutation.address] = mutation
        }
        return order.compactMap { latest[$0] }
    }

    private func customizationMutations(for item: PreferenceItem) -> [PreferenceMutation] {
        guard let customization = item.numericConfiguration else { return [] }
        guard customization.validationError(using: customizationDrafts[item.id] ?? [:]) == nil
        else { return [] }
        let parameterAddresses = Set(customization.parameters.map(\.address))
        let unchangedToggleMutations: [PreferenceMutation]
        if case .toggle(let preference) = item.control {
            unchangedToggleMutations = preference.enableMutations.filter {
                !parameterAddresses.contains($0.address)
            }
        } else {
            unchangedToggleMutations = []
        }
        return unchangedToggleMutations + customization.mutations(
            using: customizationDrafts[item.id] ?? [:]
        )
    }

    private func customizationPresetMutations(for item: PreferenceItem) -> [PreferenceMutation] {
        guard let customization = item.numericConfiguration else { return [] }
        let parameterAddresses = Set(customization.parameters.map(\.address))
        let unchangedToggleMutations: [PreferenceMutation]
        if case .toggle(let preference) = item.control {
            unchangedToggleMutations = preference.enableMutations.filter {
                !parameterAddresses.contains($0.address)
            }
        } else {
            unchangedToggleMutations = []
        }
        return unchangedToggleMutations + customization.presetMutations
    }

    private func loadCustomizationState(for item: PreferenceItem) {
        guard let customization = item.numericConfiguration else { return }
        customizationModes[item.id] = appDefaults.bool(
            forKey: customizationModeKey(itemID: item.id)
        )
        let savedDrafts = appDefaults.dictionary(
            forKey: customizationDraftsKey(itemID: item.id)
        )
        if savedDrafts != nil {
            initializedCurrentDraftItemIDs.insert(item.id)
        }
        var drafts: [String: Double] = [:]
        for parameter in customization.parameters {
            let legacyKey = customizationDraftKey(
                itemID: item.id,
                parameterID: parameter.id
            )
            let savedValue = (savedDrafts?[parameter.id] as? NSNumber)?.doubleValue ??
                (appDefaults.object(forKey: legacyKey) as? NSNumber)?.doubleValue
            if savedValue != nil { initializedCurrentDraftItemIDs.insert(item.id) }
            drafts[parameter.id] = parameter.normalized(savedValue ?? parameter.presetValue)
            if !parameter.specialValues.isEmpty {
                let savedFinite = (appDefaults.object(forKey: finiteDraftKey(
                    itemID: item.id, parameterID: parameter.id
                )) as? NSNumber)?.doubleValue
                let candidate = savedFinite ?? savedValue ?? parameter.presetValue
                finiteCustomizationDrafts[item.id, default: [:]][parameter.id] =
                    parameter.range.contains(candidate) && parameter.exactInputError(for: candidate) == nil
                        ? candidate : parameter.presetValue
            }
        }
        customizationDrafts[item.id] = drafts
    }

    private func persistCustomizationDrafts(
        _ drafts: [String: Double],
        for item: PreferenceItem
    ) {
        guard let numeric = item.numericConfiguration else { return }
        initializedCurrentDraftItemIDs.insert(item.id)
        let storedDrafts = Dictionary(uniqueKeysWithValues: numeric.parameters.map {
            ($0.id, $0.normalized(drafts[$0.id] ?? $0.presetValue))
        })
        appDefaults.set(storedDrafts, forKey: customizationDraftsKey(itemID: item.id))
    }

    private func rememberFiniteCustomizationDrafts(
        _ drafts: [String: Double], for item: PreferenceItem
    ) {
        guard let numeric = item.numericConfiguration else { return }
        for parameter in numeric.parameters where !parameter.specialValues.isEmpty {
            let candidate = drafts[parameter.id] ?? parameter.presetValue
            let value = parameter.range.contains(candidate)
                ? candidate : lastFiniteCustomizationDraft(for: item, parameter: parameter)
            guard parameter.exactInputError(for: value) == nil else { continue }
            finiteCustomizationDrafts[item.id, default: [:]][parameter.id] = value
            appDefaults.set(value, forKey: finiteDraftKey(
                itemID: item.id, parameterID: parameter.id
            ))
        }
    }

    private func finiteDraftKey(itemID: String, parameterID: String) -> String {
        "customization.\(itemID).\(parameterID).lastFiniteValue"
    }

    private func commitCustomizationModes(_ changes: [String: Bool]) {
        for (itemID, enabled) in changes {
            customizationModes[itemID] = enabled
            appDefaults.set(enabled, forKey: customizationModeKey(itemID: itemID))
        }
    }

    private func customizationModeKey(itemID: String) -> String {
        "customization.\(itemID).enabled"
    }

    private func customizationDraftKey(itemID: String, parameterID: String) -> String {
        "customization.\(itemID).\(parameterID).value"
    }

    private func customizationDraftsKey(itemID: String) -> String {
        "customization.\(itemID).drafts"
    }

    private func recoveryBaselineKey(itemID: String) -> String {
        "recovery.\(itemID).baseline"
    }

    private func loadRecoveryBaseline(for item: PreferenceItem) {
        guard case .restoreBaseline = item.recovery.strategy else { return }
        let key = recoveryBaselineKey(itemID: item.id)
        guard let data = appDefaults.data(forKey: key) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(
            PersistedRecoveryBaselineEnvelope.self,
            from: data
        ), envelope.schemaVersion == 1,
           envelope.baseline.itemID == item.id,
           Set(envelope.baseline.before.map(\.address)) == Set(item.allAddresses),
           Set(envelope.baseline.lastApplied.map(\.address)) == Set(item.allAddresses) else {
            appDefaults.removeObject(forKey: key)
            return
        }
        recoveryBaselines[item.id] = envelope.baseline
    }

    @discardableResult
    private func commitRecoveryBaselines(
        _ newValues: [String: PreferenceRecoveryBaseline],
        itemIDs: Set<String>
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var persisted = true
        for itemID in itemIDs {
            let key = recoveryBaselineKey(itemID: itemID)
            guard let baseline = newValues[itemID] else {
                recoveryBaselines[itemID] = nil
                appDefaults.removeObject(forKey: key)
                if appDefaults.object(forKey: key) != nil {
                    persisted = false
                }
                continue
            }
            let envelope = PersistedRecoveryBaselineEnvelope(
                schemaVersion: 1,
                baseline: baseline
            )
            guard let data = try? encoder.encode(envelope) else {
                persisted = false
                continue
            }
            recoveryBaselines[itemID] = baseline
            appDefaults.set(data, forKey: key)
            if appDefaults.data(forKey: key) != data {
                persisted = false
            }
        }
        return persisted
    }
}
