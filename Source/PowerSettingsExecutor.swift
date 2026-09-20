import Darwin
import Foundation
import Security

@_silgen_name("TSAuthorizationExecuteWithPrivileges")
private func TSAuthorizationExecuteWithPrivileges(
    _ authorization: AuthorizationRef,
    _ pathToTool: UnsafePointer<CChar>,
    _ options: AuthorizationFlags,
    _ arguments: UnsafePointer<UnsafeMutablePointer<CChar>>,
    _ communicationsPipe: UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
) -> OSStatus

enum PowerSettingsError: LocalizedError, DisplayMessageError {
    case launch(LocalizedText)
    case command(LocalizedText)
    case timeout(String)
    case privilegedTimeout(String)
    case parse(LocalizedText)
    case unsupported(String)
    case authorization(OSStatus, LocalizedText)
    case verification(LocalizedText)
    case conflict(LocalizedText)

    var errorDescription: String? { displayMessage.source }

    var displayMessage: LocalizedText {
        switch self {
        case .launch(let message):
            return L("无法启动电源设置工具：\(message)")
        case .command(let message):
            return L("电源设置命令失败：\(message)")
        case .timeout(let command):
            return L("电源设置工具响应超时：\(command)")
        case .privilegedTimeout(let command):
            return L("管理员电源工具响应超时，且无法确认旧授权 helper 已退出：\(command)")
        case .parse(let message):
            return L("无法解析电源设置：\(message)")
        case .unsupported(let key):
            return L("此 Mac 不支持电源能力 \(key)")
        case .authorization(let status, let message):
            if status == errAuthorizationCanceled {
                return L("已取消管理员授权")
            }
            return L("管理员授权失败（\(status)）：\(message)")
        case .verification(let message):
            return L("管理员设置写入后的状态校验失败：\(message)")
        case .conflict(let message):
            return message
        }
    }
}

private final class PowerLockedDataBox: @unchecked Sendable {
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

/// Reads `pmset` without elevation and performs a very small allow-listed set
/// of boolean writes after macOS grants `system.privilege.admin`. No shell is
/// launched and no user-provided string reaches the privileged executable.
final class PowerSettingsExecutor: PowerSettingsExecuting, @unchecked Sendable {
    private let pmsetURL = URL(fileURLWithPath: "/usr/bin/pmset")
    private let commandTimeout: TimeInterval
    private let allowedKeys: Set<String> = [
        "ttyskeepawake",
        "proximitywake",
        "acwake"
    ]

    init(commandTimeout: TimeInterval = 5) {
        self.commandTimeout = max(0.1, commandTimeout)
    }

    func snapshots(for keys: [String]) throws -> [PowerSettingSnapshot] {
        let profiles = try readProfiles()
        return keys.compactMap { key in
            let values = PowerSource.allCases.compactMap { source -> PowerSourceValue? in
                guard let value = profiles[source]?[key] else { return nil }
                return PowerSourceValue(source: source, value: value)
            }
            guard !values.isEmpty else { return nil }
            return PowerSettingSnapshot(key: key, values: values)
        }
    }

    func snapshot(for key: String) throws -> PowerSettingSnapshot? {
        try snapshots(for: [key]).first
    }

    func verify(_ expected: [PowerSettingSnapshot]) throws {
        let current = try snapshots(for: expected.map(\.key))
        let currentByKey = Dictionary(uniqueKeysWithValues: current.map { ($0.key, $0) })
        for snapshot in expected {
            guard let actual = currentByKey[snapshot.key] else {
                throw PowerSettingsError.verification(L("\(snapshot.key) 已不再可用"))
            }
            for expectedValue in snapshot.values {
                let actualValue = actual.value(for: expectedValue.source)
                guard actualValue == expectedValue.value else {
                    throw PowerSettingsError.verification(
                        L("\(snapshot.key)（\(expectedValue.source.title)）期望 ") +
                        L("\(expectedValue.value)，实际 \(actualValue.map { LocalizedText(verbatim: String($0)) } ?? L("不可用"))")
                    )
                }
            }
        }
    }

    func ensureUnchanged(since expected: [PowerSettingSnapshot]) throws {
        do {
            try verify(expected)
        } catch {
            throw PowerSettingsError.conflict(
                L("检测到电源设置已被其他 App 或命令修改。为避免覆盖较新的值，本次撤销未执行。")
            )
        }
    }

    /// Allows each key/source pair to be in either the transaction's before
    /// or after state. This is required when recovering a process that exited
    /// between two separately authorized `pmset` writes.
    func ensureCurrentMatchesAny(
        _ allowedStates: [[PowerSettingSnapshot]],
        operation: LocalizedText
    ) throws {
        let keys = Set(allowedStates.flatMap { $0.map(\.key) })
        let current = try snapshots(for: Array(keys))
        let conflicts = Self.recoveryConflicts(
            allowedStates: allowedStates,
            current: current
        )
        guard conflicts.isEmpty else {
            throw PowerSettingsError.conflict(
                L("检测到 \(conflicts.joined(separator: "、")) 已被外部修改或不可用；为避免覆盖较新的值，\(operation)未执行。")
            )
        }
    }

    /// Pure transaction check used by both live recovery and contract tests.
    /// Each key/source pair may independently match before or after, so a
    /// partial multi-source write remains recoverable without accepting a
    /// third value.
    static func recoveryConflicts(
        allowedStates: [[PowerSettingSnapshot]],
        current: [PowerSettingSnapshot]
    ) -> [String] {
        var allowed: [String: [PowerSource: Set<Int>]] = [:]
        for state in allowedStates {
            for snapshot in state {
                for entry in snapshot.values {
                    allowed[snapshot.key, default: [:]][entry.source, default: []]
                        .insert(entry.value)
                }
            }
        }
        let currentByKey = Dictionary(uniqueKeysWithValues: current.map { ($0.key, $0) })
        var conflicts: [String] = []
        for key in allowed.keys.sorted() {
            guard let sources = allowed[key] else { continue }
            guard let currentSnapshot = currentByKey[key] else {
                conflicts.append(key)
                continue
            }
            for source in sources.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let allowedValues = sources[source] else { continue }
                guard let currentValue = currentSnapshot.value(for: source),
                      allowedValues.contains(currentValue) else {
                    conflicts.append("\(key) [\(source.rawValue)]")
                    continue
                }
            }
        }
        return conflicts
    }

    func authorized(
        _ operation: (PowerAuthorizationContext) throws -> Void
    ) throws {
        var authorization: AuthorizationRef?
        let createStatus = AuthorizationCreate(
            nil,
            nil,
            AuthorizationFlags(rawValue: 0),
            &authorization
        )
        guard createStatus == errAuthorizationSuccess, let authorization else {
            throw authorizationError(createStatus)
        }
        defer {
            AuthorizationFree(authorization, [.destroyRights])
        }

        let copyStatus: OSStatus = "system.privilege.admin".withCString { rightName in
            var item = AuthorizationItem(
                name: rightName,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                let flags: AuthorizationFlags = [
                    .interactionAllowed,
                    .extendRights,
                    .preAuthorize
                ]
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    flags,
                    nil
                )
            }
        }
        guard copyStatus == errAuthorizationSuccess else {
            throw authorizationError(copyStatus)
        }
        try operation(PowerAuthorizationContext(reference: authorization))
    }

    func apply(
        _ snapshot: PowerSettingSnapshot,
        authorization: PowerAuthorizationContext
    ) throws {
        guard let authorizationReference = authorization.reference else {
            throw PowerSettingsError.authorization(
                errAuthorizationInvalidRef,
                L("授权上下文不可用")
            )
        }
        guard allowedKeys.contains(snapshot.key) else {
            throw PowerSettingsError.unsupported(snapshot.key)
        }
        for entry in snapshot.values {
            guard [0, 1].contains(entry.value) else {
                throw PowerSettingsError.command(L("拒绝非布尔值 \(entry.value)"))
            }
            try executePrivileged(
                [entry.source.pmsetFlag, snapshot.key, String(entry.value)],
                authorization: authorizationReference
            )
        }
    }

    func restore(
        _ snapshots: [PowerSettingSnapshot],
        authorization: PowerAuthorizationContext
    ) throws {
        for snapshot in snapshots {
            try apply(snapshot, authorization: authorization)
        }
    }

    /// Restores only source/key pairs that are still in a state owned by this
    /// transaction. A third value is treated as an external change and kept.
    func restorePreservingExternalChanges(
        _ target: [PowerSettingSnapshot],
        whenCurrentMatches allowedStates: [[PowerSettingSnapshot]],
        authorization: PowerAuthorizationContext
    ) throws -> [String] {
        var allowed: [String: [PowerSource: Set<Int>]] = [:]
        for state in allowedStates {
            for snapshot in state {
                for entry in snapshot.values {
                    allowed[snapshot.key, default: [:]][entry.source, default: []]
                        .insert(entry.value)
                }
            }
        }

        var conflicts: [String] = []
        for targetSnapshot in target {
            guard let current = try snapshot(for: targetSnapshot.key) else {
                conflicts.append(targetSnapshot.key)
                continue
            }
            var safeValues: [PowerSourceValue] = []
            for entry in targetSnapshot.values {
                guard let currentValue = current.value(for: entry.source),
                      allowed[targetSnapshot.key]?[entry.source]?.contains(currentValue) == true else {
                    conflicts.append("\(targetSnapshot.key) [\(entry.source.rawValue)]")
                    continue
                }
                safeValues.append(entry)
            }
            if !safeValues.isEmpty {
                let safeSnapshot = PowerSettingSnapshot(
                    key: targetSnapshot.key,
                    values: safeValues
                )
                try apply(safeSnapshot, authorization: authorization)
                try verify([safeSnapshot])
            }
        }
        return conflicts
    }

    static func parseProfiles(_ output: String) -> [PowerSource: [String: Int]] {
        var result: [PowerSource: [String: Int]] = [:]
        var currentSource: PowerSource?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix(":") {
                currentSource = PowerSource(
                    pmsetHeader: String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                )
                continue
            }
            guard let source = currentSource else { continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2,
                  let value = Int(fields.last ?? "") else { continue }
            result[source, default: [:]][String(fields[0])] = value
        }
        return result
    }

    private func readProfiles() throws -> [PowerSource: [String: Int]] {
        let result = try run(pmsetURL, ["-g", "custom"])
        guard result.status == 0 else {
            let message = result.standardError.isEmpty
                ? result.standardOutput
                : result.standardError
            throw PowerSettingsError.command(message.isEmpty ? L("未知读取错误") : LocalizedText(verbatim: message))
        }
        let profiles = Self.parseProfiles(result.standardOutput)
        guard !profiles.isEmpty else {
            throw PowerSettingsError.parse(L("pmset 没有返回可识别的电源来源"))
        }
        return profiles
    }

    private func executePrivileged(
        _ arguments: [String],
        authorization: AuthorizationRef
    ) throws {
        var cArguments = arguments.map { strdup($0) }
        cArguments.append(nil)
        defer {
            for pointer in cArguments where pointer != nil {
                free(pointer)
            }
        }

        var communicationsPipe: UnsafeMutablePointer<FILE>?
        let status = pmsetURL.path.withCString { toolPath in
            cArguments.withUnsafeMutableBufferPointer { buffer in
                let argumentsPointer = UnsafeRawPointer(buffer.baseAddress!)
                    .assumingMemoryBound(to: UnsafeMutablePointer<CChar>.self)
                return TSAuthorizationExecuteWithPrivileges(
                    authorization,
                    toolPath,
                    AuthorizationFlags(rawValue: 0),
                    argumentsPointer,
                    &communicationsPipe
                )
            }
        }
        guard status == errAuthorizationSuccess else {
            if let communicationsPipe {
                fclose(communicationsPipe)
            }
            throw authorizationError(status)
        }

        guard let communicationsPipe else {
            throw PowerSettingsError.command(L("管理员工具未返回可等待的通信管道"))
        }
        try drainPrivilegedPipe(
            communicationsPipe,
            command: ([pmsetURL.path] + arguments).joined(separator: " ")
        )
    }

    /// AuthorizationExecuteWithPrivileges exposes no child Process/PID, only a
    /// FILE stream that reaches EOF when the helper exits. Poll that descriptor
    /// in non-blocking mode so a stalled helper cannot occupy the settings queue
    /// forever. Closing the stream on every path also prevents descriptor leaks.
    private func drainPrivilegedPipe(
        _ stream: UnsafeMutablePointer<FILE>,
        command: String
    ) throws {
        defer { fclose(stream) }
        let descriptor = fileno(stream)
        guard descriptor >= 0 else {
            throw PowerSettingsError.command(L("管理员工具通信管道无效"))
        }

        let existingFlags = fcntl(descriptor, F_GETFL)
        guard existingFlags >= 0,
              fcntl(descriptor, F_SETFL, existingFlags | O_NONBLOCK) >= 0 else {
            throw PowerSettingsError.command(
                L("无法将管理员工具通信管道设为非阻塞模式：\(String(cString: strerror(errno)))")
            )
        }

        let deadline = DispatchTime.now() + commandTimeout
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            let deadlineNanoseconds = deadline.uptimeNanoseconds
            guard now < deadlineNanoseconds else {
                throw PowerSettingsError.privilegedTimeout(command)
            }
            let remainingNanoseconds = deadlineNanoseconds - now
            let roundedMilliseconds = (remainingNanoseconds + 999_999) / 1_000_000
            let timeoutMilliseconds = Int32(
                min(roundedMilliseconds, UInt64(Int32.max))
            )
            var descriptorState = pollfd(
                fd: descriptor,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let pollResult = withUnsafeMutablePointer(to: &descriptorState) {
                poll($0, 1, timeoutMilliseconds)
            }
            if pollResult == 0 {
                throw PowerSettingsError.privilegedTimeout(command)
            }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw PowerSettingsError.command(
                    L("等待管理员工具时出错：\(String(cString: strerror(errno)))")
                )
            }
            if descriptorState.revents & Int16(POLLNVAL) != 0 {
                throw PowerSettingsError.command(L("管理员工具通信管道已失效"))
            }

            while true {
                let byteCount = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                }
                if byteCount > 0 { continue }
                if byteCount == 0 { return }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { break }
                throw PowerSettingsError.command(
                    L("读取管理员工具结果失败：\(String(cString: strerror(errno)))")
                )
            }
        }
    }

    private func authorizationError(_ status: OSStatus) -> PowerSettingsError {
        let message = (SecCopyErrorMessageString(status, nil) as String?).map { LocalizedText(verbatim: $0) } ?? L("未知错误")
        return .authorization(status, message)
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
            throw PowerSettingsError.launch(error.displayMessage)
        }

        // Drain both pipes while pmset is running. Waiting or reading one pipe
        // first can deadlock if the other fills its kernel buffer.
        let outputData = PowerLockedDataBox()
        let errorData = PowerLockedDataBox()
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
            throw PowerSettingsError.timeout(command)
        }
        readers.wait()

        let output = outputData.load()
        let error = errorData.load()
        return ProcessResult(
            status: process.terminationStatus,
            standardOutput: String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            standardError: String(data: error, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
