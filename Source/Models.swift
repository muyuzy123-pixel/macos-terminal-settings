import Foundation

enum SettingsCategory: String, CaseIterable, Identifiable {
    case overview
    case dock
    case finder
    case screenshots
    case trackpad
    case keyboard
    case windows
    case system
    case advanced

    var id: String { rawValue }

    var title: LocalizedText {
        switch self {
        case .overview: return L("概览")
        case .dock: return L("程序坞")
        case .finder: return L("访达")
        case .screenshots: return L("截屏")
        case .trackpad: return L("触控板")
        case .keyboard: return L("键盘")
        case .windows: return L("窗口与对话框")
        case .system: return L("系统与开发")
        case .advanced: return L("高级")
        }
    }

    var subtitle: LocalizedText {
        switch self {
        case .overview: return L("安全地管理隐藏偏好")
        case .dock: return L("显示、布局与多显示器")
        case .finder: return L("路径、动画与磁盘元数据")
        case .screenshots: return L("格式、阴影与文件名")
        case .trackpad: return L("仅终端可写的遗留手势实验")
        case .keyboard: return L("重复输入与按键响应")
        case .windows: return L("保存、窗口交互与动画")
        case .system: return L("菜单栏、Time Machine 与开发")
        case .advanced: return L("需要管理员授权的隐藏能力")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "slider.horizontal.3"
        case .dock: return "dock.rectangle"
        case .finder: return "face.smiling"
        case .screenshots: return "camera.viewfinder"
        case .trackpad: return "hand.draw"
        case .keyboard: return "keyboard"
        case .windows: return "macwindow.on.rectangle"
        case .system: return "gearshape.2"
        case .advanced: return "lock.shield"
        }
    }
}

enum PreferenceValue: Equatable, Codable {
    case bool(Bool)
    case integer(Int)
    case float(Double)
    case string(String)

    private static func floatsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        if lhs == rhs { return true }
        guard lhs.isFinite, rhs.isFinite else { return false }
        let scale = max(1, max(abs(lhs), abs(rhs)))
        return abs(lhs - rhs) <= scale * 0.000_000_1
    }

    var defaultsArguments: [String] {
        switch self {
        case .bool(let value):
            return ["-bool", value ? "true" : "false"]
        case .integer(let value):
            return ["-int", String(value)]
        case .float(let value):
            return ["-float", Self.format(value)]
        case .string(let value):
            return ["-string", value]
        }
    }

    func matches(raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .bool(let expected):
            let normalized = value.lowercased()
            if ["1", "true", "yes"].contains(normalized) { return expected }
            if ["0", "false", "no"].contains(normalized) { return !expected }
            return false
        case .integer(let expected):
            return Int(value) == expected
        case .float(let expected):
            guard let parsed = Double(value) else { return false }
            return abs(parsed - expected) < 0.0001
        case .string(let expected):
            return value == expected
        }
    }

    /// Compares values without discarding their plist scalar type. Float values
    /// retain only a sub-step serialization tolerance; the smallest supported
    /// editing step is 0.001, so a distinct user value must never compare equal.
    func matches(_ actual: PreferenceValue) -> Bool {
        switch (self, actual) {
        case (.bool(let expected), .bool(let value)):
            return expected == value
        case (.integer(let expected), .integer(let value)):
            return expected == value
        case (.float(let expected), .float(let value)):
            return Self.floatsMatch(expected, value)
        case (.string(let expected), .string(let value)):
            return expected == value
        default:
            return false
        }
    }

    var displayValue: String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .float(let value): return Self.format(value)
        case .string(let value): return value
        }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value,
           value >= Double(Int.min), value <= Double(Int.max) {
            return String(Int(value))
        }
        return String(
            format: "%.15g",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}

enum PreferenceHostScope: String, Codable {
    case currentUser
    case currentHost
}

struct PreferenceAddress: Hashable, Codable {
    let domain: String
    let key: String
    let hostScope: PreferenceHostScope

    init(
        domain: String,
        key: String,
        hostScope: PreferenceHostScope = .currentUser
    ) {
        self.domain = domain
        self.key = key
        self.hostScope = hostScope
    }

    private enum CodingKeys: String, CodingKey {
        case domain
        case key
        case hostScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decode(String.self, forKey: .domain)
        key = try container.decode(String.self, forKey: .key)
        // 1.1.0 undo records did not store a host scope. Treat them as the
        // ordinary current-user domain so persisted undo remains compatible.
        hostScope = try container.decodeIfPresent(
            PreferenceHostScope.self,
            forKey: .hostScope
        ) ?? .currentUser
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encode(key, forKey: .key)
        if hostScope != .currentUser {
            try container.encode(hostScope, forKey: .hostScope)
        }
    }

    var displayPath: LocalizedText {
        let scope: LocalizedText = hostScope == .currentHost ? L("（当前主机）") : ""
        return L("\(domain) / \(key)\(scope)")
    }
}

struct PreferenceMutation: Identifiable {
    let address: PreferenceAddress
    let value: PreferenceValue?

    var id: String { "\(address.hostScope.rawValue)::\(address.domain)::\(address.key)" }

    static func write(_ domain: String, _ key: String, _ value: PreferenceValue) -> PreferenceMutation {
        PreferenceMutation(address: PreferenceAddress(domain: domain, key: key), value: value)
    }

    static func delete(_ domain: String, _ key: String) -> PreferenceMutation {
        PreferenceMutation(address: PreferenceAddress(domain: domain, key: key), value: nil)
    }

    static func writeCurrentHost(
        _ domain: String,
        _ key: String,
        _ value: PreferenceValue
    ) -> PreferenceMutation {
        PreferenceMutation(
            address: PreferenceAddress(domain: domain, key: key, hostScope: .currentHost),
            value: value
        )
    }

    static func deleteCurrentHost(_ domain: String, _ key: String) -> PreferenceMutation {
        PreferenceMutation(
            address: PreferenceAddress(domain: domain, key: key, hostScope: .currentHost),
            value: nil
        )
    }

    var command: String {
        let domain = Self.shellQuote(address.domain)
        let key = Self.shellQuote(address.key)
        let scope = address.hostScope == .currentHost ? " -currentHost" : ""
        guard let value else {
            return "defaults\(scope) delete \(domain) \(key)"
        }
        let arguments = value.defaultsArguments.map(Self.shellQuote).joined(separator: " ")
        return "defaults\(scope) write \(domain) \(key) \(arguments)"
    }

    private static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct TogglePreference {
    let readAddress: PreferenceAddress
    let enabledValue: PreferenceValue
    let enableMutations: [PreferenceMutation]
    let disableMutations: [PreferenceMutation]
}

struct ChoiceOption: Identifiable {
    let id: String
    let title: LocalizedText
    let value: PreferenceValue?
}

struct ChoicePreference {
    let address: PreferenceAddress
    let options: [ChoiceOption]
}

struct TextPreference {
    let address: PreferenceAddress
    let placeholder: LocalizedText
}

struct PrivilegedTogglePreference {
    let key: String

    func command(enabled: Bool) -> String {
        "sudo pmset -a \(key) \(enabled ? 1 : 0)"
    }
}

enum PowerSource: String, Codable, CaseIterable, Hashable {
    case battery
    case charger
    case ups

    var title: LocalizedText {
        switch self {
        case .battery: return L("电池")
        case .charger: return L("电源适配器")
        case .ups: return "UPS"
        }
    }

    var pmsetFlag: String {
        switch self {
        case .battery: return "-b"
        case .charger: return "-c"
        case .ups: return "-u"
        }
    }

    init?(pmsetHeader: String) {
        switch pmsetHeader {
        case "Battery Power": self = .battery
        case "AC Power": self = .charger
        case "UPS Power": self = .ups
        default: return nil
        }
    }
}

struct PowerSourceValue: Codable, Equatable {
    let source: PowerSource
    let value: Int
}

struct PowerSettingSnapshot: Codable, Equatable {
    let key: String
    let values: [PowerSourceValue]

    func value(for source: PowerSource) -> Int? {
        values.first(where: { $0.source == source })?.value
    }
}

enum NumericPreferenceStorage {
    case integer
    case float

    func value(for displayedValue: Double, scale: Double) -> PreferenceValue {
        let storedValue = displayedValue * scale
        switch self {
        case .integer:
            return .integer(Int(storedValue.rounded()))
        case .float:
            return .float(storedValue)
        }
    }
}

enum NumericPreferenceReadingPolicy {
    case strictStorage
    case integerOrFloat
}

struct NumericPreferenceSpecialValue: Identifiable {
    let value: Double
    let title: LocalizedText

    var id: Double { value }
}

struct NumericPreferencePreset: Identifiable {
    let value: Double
    let title: LocalizedText

    var id: Double { value }
}

enum NumericPreferenceCurrentValue: Equatable {
    case loading
    case notSet
    case value(Double, rawValue: PreferenceValue? = nil)
    case invalid(String)
    case unavailable(LocalizedText)

    var loadableValue: Double? {
        guard case .value(let value, _) = self else { return nil }
        return value
    }
}

/// A single bounded value exposed by a preference item's optional advanced UI.
/// Ranges are expressed in the unit shown to the user; `storageScale` converts
/// that value to the unit expected by `defaults` (for example seconds to ms).
struct NumericPreferenceParameter: Identifiable {
    static let maximumSteppedSliderValueCount = 128

    let id: String
    let title: LocalizedText
    let detail: LocalizedText
    let address: PreferenceAddress
    let range: ClosedRange<Double>
    let step: Double
    let presetValue: Double
    let storage: NumericPreferenceStorage
    let readingPolicy: NumericPreferenceReadingPolicy
    let storageScale: Double
    let unit: LocalizedText
    let precision: Int
    let specialValues: [NumericPreferenceSpecialValue]
    let presets: [NumericPreferencePreset]

    init(
        id: String,
        title: LocalizedText,
        detail: LocalizedText,
        address: PreferenceAddress,
        range: ClosedRange<Double>,
        step: Double,
        presetValue: Double,
        storage: NumericPreferenceStorage,
        storageScale: Double = 1,
        unit: LocalizedText,
        precision: Int,
        readingPolicy: NumericPreferenceReadingPolicy = .strictStorage,
        specialValues: [NumericPreferenceSpecialValue] = [],
        presets: [NumericPreferencePreset] = []
    ) {
        precondition(range.lowerBound <= presetValue && presetValue <= range.upperBound)
        precondition(step > 0 && storageScale > 0)
        precondition(specialValues.allSatisfy { $0.value.isFinite && !range.contains($0.value) })
        precondition(Set(specialValues.map(\.value)).count == specialValues.count)
        self.id = id
        self.title = title
        self.detail = detail
        self.address = address
        self.range = range
        self.step = step
        self.presetValue = presetValue
        self.storage = storage
        self.readingPolicy = readingPolicy
        self.storageScale = storageScale
        self.unit = unit
        self.precision = precision
        self.specialValues = specialValues
        self.presets = presets
        precondition(presets.allSatisfy { exactInputError(for: $0.value) == nil })
    }

    func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return presetValue }
        if specialValue(for: value) != nil { return value }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let stepCount = ((clamped - range.lowerBound) / step).rounded()
        let stepped = range.lowerBound + stepCount * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    /// SwiftUI 26 enumerates every value supplied to its stepped Slider tick
    /// closure, even when the closure returns no visible tick. Dense ranges such
    /// as 0...2 / 0.001 therefore perform 2,001 callbacks whenever the control is
    /// laid out. Those ranges use a continuous visual track while the Binding
    /// still normalizes every value to the exact model step.
    var discreteValueCount: Int {
        let intervalCount = ((range.upperBound - range.lowerBound) / step).rounded()
        guard intervalCount.isFinite,
              intervalCount >= 0,
              intervalCount < Double(Int.max) else {
            return .max
        }
        return Int(intervalCount) + 1
    }

    var usesContinuousSliderTrack: Bool {
        discreteValueCount > Self.maximumSteppedSliderValueCount
    }

    func preferenceValue(for value: Double) -> PreferenceValue {
        storage.value(for: normalized(value), scale: storageScale)
    }

    func displayedValue(from storedValue: PreferenceValue) -> Double? {
        let rawValue: Double
        switch readingPolicy {
        case .strictStorage:
            switch (storage, storedValue) {
            case (.integer, .integer(let value)):
                rawValue = Double(value)
            case (.float, .float(let value)):
                rawValue = value
            default:
                return nil
            }
        case .integerOrFloat:
            switch storedValue {
            case .integer(let value): rawValue = Double(value)
            case .float(let value): rawValue = value
            case .bool, .string: return nil
            }
        }
        let displayed = rawValue / storageScale
        guard exactInputError(for: displayed) == nil else { return nil }
        return displayed
    }

    func currentValue(from storedValue: PreferenceValue?) -> NumericPreferenceCurrentValue {
        guard let storedValue else { return .notSet }
        guard let displayedValue = displayedValue(from: storedValue) else {
            return .invalid(storedValue.displayValue)
        }
        return .value(displayedValue, rawValue: storedValue)
    }

    func exactInputError(for value: Double) -> LocalizedText? {
        guard value.isFinite else { return L("请输入有限数值") }
        if specialValue(for: value) != nil { return nil }
        guard range.contains(value) else { return L("允许范围为 \(rangeLabel)") }
        let normalizedValue = normalized(value)
        let tolerance = max(step / 10_000, 0.000_000_1)
        guard abs(normalizedValue - value) <= tolerance else {
            return L("请输入 \(displayValue(step)) 的整数倍")
        }
        return nil
    }

    func displayValue(_ value: Double, region: Locale = .autoupdatingCurrent) -> LocalizedText {
        if let specialValue = specialValue(for: value) { return specialValue.title }
        let normalizedValue = normalized(value)
        let number: String
        if precision == 0 {
            number = String(Int(normalizedValue.rounded()))
        } else {
            number = String(format: "%.*f", locale: region, precision, normalizedValue)
        }
        return unit.isEmpty ? LocalizedText(verbatim: number) : L("\(number) \(unit)")
    }

    var rangeLabel: LocalizedText {
        L("\(displayValue(range.lowerBound))–\(displayValue(range.upperBound))")
    }

    func specialValue(for value: Double) -> NumericPreferenceSpecialValue? {
        specialValues.first { $0.value == value }
    }
}

struct PreferenceCustomization {
    let detail: LocalizedText
    let parameters: [NumericPreferenceParameter]

    var presetSummary: LocalizedText {
        parameters.map { L("\($0.title) \($0.displayValue($0.presetValue))") }
            .joined(separator: L("；"))
    }

    func mutations(using drafts: [String: Double]) -> [PreferenceMutation] {
        parameters.map { parameter in
            let value = drafts[parameter.id] ?? parameter.presetValue
            return PreferenceMutation(
                address: parameter.address,
                value: parameter.preferenceValue(for: value)
            )
        }
    }

    var presetMutations: [PreferenceMutation] {
        mutations(using: [:])
    }
}

/// A numeric setting that is independently editable rather than being hidden
/// behind a synthetic parent toggle or choice. It intentionally reuses the
/// same bounded parameter contract as existing customization panels.
enum NumericPreferenceConstraint {
    case ordered(lowerParameterID: String, upperParameterID: String, message: LocalizedText)

    func validationError(using drafts: [String: Double]) -> LocalizedText? {
        switch self {
        case .ordered(let lowerID, let upperID, let message):
            guard let lower = drafts[lowerID], let upper = drafts[upperID], lower <= upper else {
                return message
            }
            return nil
        }
    }
}

struct NumericPreference {
    let detail: LocalizedText
    let parameters: [NumericPreferenceParameter]
    let constraints: [NumericPreferenceConstraint]
    let initializesDraftsFromCurrentValue: Bool

    init(
        detail: LocalizedText,
        parameters: [NumericPreferenceParameter],
        constraints: [NumericPreferenceConstraint] = [],
        initializesDraftsFromCurrentValue: Bool = false
    ) {
        self.detail = detail
        self.parameters = parameters
        self.constraints = constraints
        self.initializesDraftsFromCurrentValue = initializesDraftsFromCurrentValue
    }

    var presetSummary: LocalizedText {
        parameters.map { L("\($0.title) \($0.displayValue($0.presetValue))") }
            .joined(separator: L("；"))
    }

    func mutations(using drafts: [String: Double]) -> [PreferenceMutation] {
        guard validationError(using: drafts) == nil else { return [] }
        return parameters.map { parameter in
            let value = drafts[parameter.id] ?? parameter.presetValue
            return PreferenceMutation(
                address: parameter.address,
                value: parameter.preferenceValue(for: value)
            )
        }
    }

    var presetMutations: [PreferenceMutation] {
        mutations(using: [:])
    }

    func validationError(using drafts: [String: Double]) -> LocalizedText? {
        var resolved: [String: Double] = [:]
        for parameter in parameters {
            let value = drafts[parameter.id] ?? parameter.presetValue
            if let error = parameter.exactInputError(for: value) {
                return L("\(parameter.title)：\(error)")
            }
            resolved[parameter.id] = value
        }
        return constraints.lazy.compactMap { $0.validationError(using: resolved) }.first
    }

    func currentValues(
        using values: [PreferenceAddress: PreferenceValue]
    ) -> [String: NumericPreferenceCurrentValue] {
        var result: [String: NumericPreferenceCurrentValue] = [:]
        for parameter in parameters {
            result[parameter.id] = parameter.currentValue(from: values[parameter.address])
        }
        return result
    }

    func loadableDrafts(
        from currentValues: [String: NumericPreferenceCurrentValue]
    ) -> [String: Double]? {
        var drafts: [String: Double] = [:]
        for parameter in parameters {
            guard let value = currentValues[parameter.id]?.loadableValue else {
                return nil
            }
            drafts[parameter.id] = value
        }
        return validationError(using: drafts) == nil ? drafts : nil
    }

    func expectedSnapshots(
        from currentValues: [String: NumericPreferenceCurrentValue]
    ) -> [PreferenceSnapshot]? {
        var snapshots: [PreferenceSnapshot] = []
        for parameter in parameters {
            guard let state = currentValues[parameter.id] else { return nil }
            let value: PreferenceValue?
            switch state {
            case .notSet:
                value = nil
            case .value(let displayedValue, let rawValue):
                // Keep the original plist scalar type for compare-and-swap and
                // restoration, even when this parameter accepts both numeric types.
                value = rawValue ?? parameter.preferenceValue(for: displayedValue)
            case .loading, .invalid, .unavailable:
                return nil
            }
            snapshots.append(PreferenceSnapshot(address: parameter.address, value: value))
        }
        return snapshots
    }
}

enum PreferenceControl {
    case toggle(TogglePreference)
    case choice(ChoicePreference)
    case text(TextPreference)
    case numeric(NumericPreference)
    case privilegedToggle(PrivilegedTogglePreference)
}

enum PreferenceCaution: String {
    case none
    case interaction
    case compatibility
    case privileged

    var label: LocalizedText? {
        switch self {
        case .none: return nil
        case .interaction: return L("交互变化")
        case .compatibility: return L("实验性")
        case .privileged: return L("需要管理员权限")
        }
    }

    var risk: PreferenceRisk {
        switch self {
        case .none: return .low
        case .interaction: return .medium
        case .compatibility: return .experimental
        case .privileged: return .privileged
        }
    }
}

enum PreferenceRisk: String {
    case low
    case medium
    case experimental
    case privileged

    var label: LocalizedText {
        switch self {
        case .low: return L("低风险")
        case .medium: return L("需留意交互")
        case .experimental: return L("实验性")
        case .privileged: return L("管理员级操作")
        }
    }
}

/// Separates implementation stability from operation risk. A preference can be
/// safe to write and delete while its value semantics or visible effect remain
/// uncertain on the current macOS release.
enum PreferenceStability: Equatable {
    case stable
    case unstable(LocalizedText)

    var label: LocalizedText? {
        switch self {
        case .stable: return nil
        case .unstable: return L("不稳定")
        }
    }

    var note: LocalizedText? {
        guard case .unstable(let note) = self else { return nil }
        return note
    }

    var isUnstable: Bool {
        note != nil
    }
}

enum PreferenceSupport: Equatable {
    case supported
    case unverified(LocalizedText)
    case unsupported(LocalizedText)
}

struct PreferenceCompatibility {
    let minimumMajorVersion: Int
    let verifiedMajorVersion: Int
    let verifiedMinorVersion: Int
    let verifiedPatchVersion: Int
    let verifiedOSVersion: String
    let verifiedDate: String

    static let current = PreferenceCompatibility(
        minimumMajorVersion: 14,
        verifiedMajorVersion: 26,
        verifiedMinorVersion: 6,
        verifiedPatchVersion: 2,
        verifiedOSVersion: "macOS 26.6.2",
        verifiedDate: "2026-09-12"
    )

    func support(for version: OperatingSystemVersion) -> PreferenceSupport {
        if version.majorVersion < minimumMajorVersion {
            return .unsupported(L("需要 macOS \(minimumMajorVersion) 或更高版本"))
        }
        let runningVersion = (
            version.majorVersion,
            version.minorVersion,
            version.patchVersion
        )
        let verifiedVersion = (
            verifiedMajorVersion,
            verifiedMinorVersion,
            verifiedPatchVersion
        )
        if runningVersion > verifiedVersion {
            let runningDescription = [
                version.majorVersion,
                version.minorVersion,
                version.patchVersion
            ].map(String.init).joined(separator: ".")
            return .unverified(
                L("尚未在 macOS \(runningDescription) 验证；最新验证版本为 \(verifiedOSVersion)")
            )
        }
        return .supported
    }

    var summary: LocalizedText {
        L("macOS \(minimumMajorVersion)+ · 验证于 \(verifiedOSVersion)（\(verifiedDate)）")
    }
}

struct PreferenceEvidence {
    let title: LocalizedText
    let url: String?

    static let curated = PreferenceEvidence(
        title: L("本项目验证清单与社区资料"),
        url: "https://github.com/yannbertrand/macos-defaults"
    )
}

enum PreferenceExposure: String, CaseIterable {
    case terminalOnly
    case systemSettingsEnhancement
    case systemSettingsMirror

    var label: LocalizedText {
        switch self {
        case .terminalOnly: return L("仅终端")
        case .systemSettingsEnhancement: return L("系统设置增强")
        case .systemSettingsMirror: return L("系统设置镜像")
        }
    }
}

enum PreferenceEnhancementKind: String {
    case exactValue
    case extendedRange
    case extraOption

    var label: LocalizedText {
        switch self {
        case .exactValue: return L("精确值")
        case .extendedRange: return L("扩展范围")
        case .extraOption: return L("额外选项")
        }
    }
}

enum SystemSettingsCoverage: String {
    case exact
    case extended
    case related
    case noneObserved
    case unchecked

    var label: LocalizedText {
        switch self {
        case .exact: return L("等价入口")
        case .extended: return L("基础入口")
        case .related: return L("相关入口")
        case .noneObserved: return L("当前版本未检出")
        case .unchecked: return L("尚未核对")
        }
    }
}

struct SystemSettingsReference {
    let coverage: SystemSettingsCoverage
    let pathSegments: [LocalizedText]
    let verifiedOSVersion: String
    let note: LocalizedText

    var path: LocalizedText {
        pathSegments.joined(separator: " → ")
    }
}

struct PreferenceSource {
    let exposure: PreferenceExposure
    let enhancementKind: PreferenceEnhancementKind?
    let systemSettings: SystemSettingsReference?
    let note: LocalizedText?

    static let terminalOnly = PreferenceSource(
        exposure: .terminalOnly,
        enhancementKind: nil,
        systemSettings: nil,
        note: nil
    )

    var detailLabel: LocalizedText {
        guard let enhancementKind else { return exposure.label }
        return L("\(exposure.label) · \(enhancementKind.label)")
    }
}

enum PreferenceRecoveryStrategy {
    case deleteExplicit
    case writePreset([PreferenceMutation])
    case restoreBaseline
    case unavailable(LocalizedText)
}

struct PreferenceRecovery {
    let strategy: PreferenceRecoveryStrategy
    let actionTitle: LocalizedText
    let detail: LocalizedText

    static let deleteExplicit = PreferenceRecovery(
        strategy: .deleteExplicit,
        actionTitle: L("删除当前显式值"),
        detail: L("删除该键在当前用户域中的显式值，不论它最初由本应用、其他工具还是用户命令写入；随后采用当前有效的 Apple 默认值或组织强制值。")
    )

    static let restoreBaseline = PreferenceRecovery(
        strategy: .restoreBaseline,
        actionTitle: L("恢复接管前值"),
        detail: L("恢复本应用首次修改前记录的精确值和缺失状态；如检测到外部修改则不会覆盖。")
    )

    var isAvailableInPrinciple: Bool {
        if case .unavailable = strategy { return false }
        return true
    }
}

enum PreferenceManagementState: Equatable {
    case checking
    case unmanaged
    case forced([PreferenceAddress])
    case partiallyForced([PreferenceAddress])
    case unknown(LocalizedText)
    case notApplicable

    var isReadOnly: Bool {
        switch self {
        case .unmanaged, .notApplicable: return false
        case .checking, .forced, .partiallyForced, .unknown: return true
        }
    }

    var label: LocalizedText? {
        switch self {
        case .checking: return L("检查管理状态")
        case .unmanaged, .notApplicable: return nil
        case .forced: return L("由组织管理")
        case .partiallyForced: return L("部分由组织管理")
        case .unknown: return L("管理状态未知")
        }
    }
}

enum PreferenceReadState: Equatable {
    case loading
    case systemDefault
    case disabled
    case enabled
    case configured(LocalizedText)
    case unverified(LocalizedText)
    case unsupported(LocalizedText)
    case error(LocalizedText)

    var label: LocalizedText {
        switch self {
        case .loading: return L("正在读取")
        case .systemDefault: return L("系统默认")
        case .disabled: return L("已关闭")
        case .enabled: return L("已启用")
        case .configured(let value): return value.isEmpty ? L("已配置") : L("已配置：\(value)")
        case .unverified: return L("当前系统未验证")
        case .unsupported: return L("当前系统不支持")
        case .error: return L("读取失败")
        }
    }

    var isExplicitlyConfigured: Bool {
        switch self {
        case .enabled, .configured: return true
        default: return false
        }
    }
}

enum PreferenceDisplayText {
    static func disclosureLabel(title: LocalizedText, action: LocalizedText) -> LocalizedText {
        L("\(title)：\(action)")
    }
}

struct PreferenceItem: Identifiable {
    let id: String
    let category: SettingsCategory
    let title: LocalizedText
    let detail: LocalizedText
    let symbol: String
    let control: PreferenceControl
    let restartProcesses: [String]
    let effectHint: LocalizedText
    let caution: PreferenceCaution
    let stability: PreferenceStability
    let compatibility: PreferenceCompatibility
    let evidence: PreferenceEvidence
    let customization: PreferenceCustomization?
    let source: PreferenceSource
    let recovery: PreferenceRecovery
    /// Read-only context is excluded from mutation, undo and recovery addresses.
    let contextAddresses: [PreferenceAddress]
    let lockingContextAddresses: [PreferenceAddress]

    init(
        id: String,
        category: SettingsCategory,
        title: LocalizedText,
        detail: LocalizedText,
        symbol: String,
        control: PreferenceControl,
        restartProcesses: [String],
        effectHint: LocalizedText,
        caution: PreferenceCaution,
        stability: PreferenceStability = .stable,
        compatibility: PreferenceCompatibility = .current,
        evidence: PreferenceEvidence = .curated,
        customization: PreferenceCustomization? = nil,
        source: PreferenceSource = .terminalOnly,
        recovery: PreferenceRecovery = .deleteExplicit,
        contextAddresses: [PreferenceAddress] = [],
        lockingContextAddresses: [PreferenceAddress] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.control = control
        self.restartProcesses = restartProcesses
        self.effectHint = effectHint
        self.caution = caution
        self.stability = stability
        self.compatibility = compatibility
        self.evidence = evidence
        self.customization = customization
        self.source = source
        self.recovery = recovery
        precondition(Set(lockingContextAddresses).isSubset(of: Set(contextAddresses)))
        self.contextAddresses = contextAddresses
        self.lockingContextAddresses = lockingContextAddresses
    }

    var numericConfiguration: NumericPreference? {
        switch control {
        case .numeric(let preference):
            return preference
        default:
            guard let customization else { return nil }
            return NumericPreference(
                detail: customization.detail,
                parameters: customization.parameters
            )
        }
    }

    var allAddresses: [PreferenceAddress] {
        let controlAddresses: [PreferenceAddress]
        switch control {
        case .toggle(let preference):
            controlAddresses = (preference.enableMutations + preference.disableMutations).map(\.address)
        case .choice(let preference):
            controlAddresses = [preference.address]
        case .text(let preference):
            controlAddresses = [preference.address]
        case .numeric(let preference):
            controlAddresses = preference.parameters.map(\.address)
        case .privilegedToggle:
            controlAddresses = []
        }
        let customizationAddresses = customization?.parameters.map(\.address) ?? []
        var seen = Set<PreferenceAddress>()
        return (controlAddresses + customizationAddresses).filter { seen.insert($0).inserted }
    }

    var readAddresses: [PreferenceAddress] {
        var seen = Set<PreferenceAddress>()
        return (allAddresses + contextAddresses).filter { seen.insert($0).inserted }
    }

    var requiresAdministrator: Bool {
        if case .privilegedToggle = control { return true }
        return false
    }

    var supportsRecoveryAction: Bool {
        !requiresAdministrator && recovery.isAvailableInPrinciple
    }

    var privilegedKey: String? {
        guard case .privilegedToggle(let preference) = control else { return nil }
        return preference.key
    }

    func support(
        for version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> PreferenceSupport {
        compatibility.support(for: version)
    }
}

struct PreferenceRecoveryBaseline: Codable, Equatable {
    let itemID: String
    let before: [PreferenceSnapshot]
    let lastApplied: [PreferenceSnapshot]
    let createdAt: Date
}

struct PersistedRecoveryBaselineEnvelope: Codable {
    let schemaVersion: Int
    let baseline: PreferenceRecoveryBaseline
}

struct PreferenceRecoveryPlan {
    let mutations: [PreferenceMutation]
    let expectedCurrent: [PreferenceSnapshot]
    let clearsBaseline: Bool
}

extension PreferenceItem {
    func recoveryPlan(
        baseline: PreferenceRecoveryBaseline?
    ) -> PreferenceRecoveryPlan? {
        switch recovery.strategy {
        case .deleteExplicit:
            return PreferenceRecoveryPlan(
                mutations: allAddresses.map {
                    PreferenceMutation(address: $0, value: nil)
                },
                expectedCurrent: [],
                clearsBaseline: false
            )
        case .writePreset(let mutations):
            let expectedAddresses = Set(allAddresses)
            guard mutations.count == expectedAddresses.count,
                  Set(mutations.map(\.address)) == expectedAddresses else {
                return nil
            }
            return PreferenceRecoveryPlan(
                mutations: mutations,
                expectedCurrent: [],
                clearsBaseline: false
            )
        case .restoreBaseline:
            guard let baseline, baseline.itemID == id else { return nil }
            let expectedAddresses = Set(allAddresses)
            guard baseline.before.count == expectedAddresses.count,
                  baseline.lastApplied.count == expectedAddresses.count,
                  Set(baseline.before.map(\.address)) == expectedAddresses,
                  Set(baseline.lastApplied.map(\.address)) == expectedAddresses else {
                return nil
            }
            return PreferenceRecoveryPlan(
                mutations: baseline.before.map {
                    PreferenceMutation(address: $0.address, value: $0.value)
                },
                expectedCurrent: baseline.lastApplied,
                clearsBaseline: true
            )
        case .unavailable:
            return nil
        }
    }
}

struct PreferenceSnapshot: Codable, Equatable {
    let address: PreferenceAddress
    let value: PreferenceValue?
}

struct UndoRecord: Codable {
    let title: String
    let displayAction: LocalizedText?
    let before: [PreferenceSnapshot]
    let after: [PreferenceSnapshot]
    let restartProcesses: [String]
    let createdAt: Date
    let customizationBefore: [String: Bool]?
    let customizationAfter: [String: Bool]?
    let powerBefore: [PowerSettingSnapshot]?
    let powerAfter: [PowerSettingSnapshot]?
    let recoveryItemIDs: [String]?
    let recoveryBefore: [String: PreferenceRecoveryBaseline]?
    let recoveryAfter: [String: PreferenceRecoveryBaseline]?

    init(
        title: String,
        displayAction: LocalizedText? = nil,
        before: [PreferenceSnapshot],
        after: [PreferenceSnapshot],
        restartProcesses: [String],
        createdAt: Date,
        customizationBefore: [String: Bool]? = nil,
        customizationAfter: [String: Bool]? = nil,
        powerBefore: [PowerSettingSnapshot]? = nil,
        powerAfter: [PowerSettingSnapshot]? = nil,
        recoveryItemIDs: [String]? = nil,
        recoveryBefore: [String: PreferenceRecoveryBaseline]? = nil,
        recoveryAfter: [String: PreferenceRecoveryBaseline]? = nil
    ) {
        self.title = title
        self.displayAction = displayAction
        self.before = before
        self.after = after
        self.restartProcesses = restartProcesses
        self.createdAt = createdAt
        self.customizationBefore = customizationBefore
        self.customizationAfter = customizationAfter
        self.powerBefore = powerBefore
        self.powerAfter = powerAfter
        self.recoveryItemIDs = recoveryItemIDs
        self.recoveryBefore = recoveryBefore
        self.recoveryAfter = recoveryAfter
    }

    private enum CodingKeys: String, CodingKey {
        case title, displayAction, before, after, restartProcesses, createdAt
        case customizationBefore, customizationAfter, powerBefore, powerAfter
        case recoveryItemIDs, recoveryBefore, recoveryAfter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        // Display-only data must never invalidate a recoverable transaction.
        displayAction = try? c.decode(LocalizedText.self, forKey: .displayAction)
        before = try c.decode([PreferenceSnapshot].self, forKey: .before)
        after = try c.decode([PreferenceSnapshot].self, forKey: .after)
        restartProcesses = try c.decode([String].self, forKey: .restartProcesses)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        customizationBefore = try c.decodeIfPresent([String: Bool].self, forKey: .customizationBefore)
        customizationAfter = try c.decodeIfPresent([String: Bool].self, forKey: .customizationAfter)
        powerBefore = try c.decodeIfPresent([PowerSettingSnapshot].self, forKey: .powerBefore)
        powerAfter = try c.decodeIfPresent([PowerSettingSnapshot].self, forKey: .powerAfter)
        recoveryItemIDs = try c.decodeIfPresent([String].self, forKey: .recoveryItemIDs)
        recoveryBefore = try c.decodeIfPresent([String: PreferenceRecoveryBaseline].self, forKey: .recoveryBefore)
        recoveryAfter = try c.decodeIfPresent([String: PreferenceRecoveryBaseline].self, forKey: .recoveryAfter)
    }

    func localizedTitle(resources: LocalizationResources = .main) -> LocalizedText {
        guard let displayAction, displayAction.isKnown(to: resources) else {
            return LocalizedText(verbatim: title)
        }
        return displayAction
    }
}

struct PersistedUndoEnvelope: Codable {
    let schemaVersion: Int
    let record: UndoRecord
}

/// Durable write-ahead record for either an ordinary preference transaction
/// or an allow-listed power transaction. It is stored before the first
/// `defaults`/`pmset` mutation so a crash between two writes can be recovered
/// without guessing the user's earlier values.
struct PersistedPendingPreferenceEnvelope: Codable {
    let schemaVersion: Int
    let record: UndoRecord
}
