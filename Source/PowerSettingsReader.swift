import Darwin
import Foundation

enum PowerSettingsError: LocalizedError, DisplayMessageError {
    case launch(LocalizedText)
    case command(LocalizedText)
    case timeout(String)
    case parse(LocalizedText)

    var errorDescription: String? { displayMessage.source }

    var displayMessage: LocalizedText {
        switch self {
        case .launch(let message):
            return L("无法启动电源设置工具：\(message)")
        case .command(let message):
            return L("电源设置命令失败：\(message)")
        case .timeout(let command):
            return L("电源设置工具响应超时：\(command)")
        case .parse(let message):
            return L("无法解析电源设置：\(message)")
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

/// Reads `pmset` without elevation. The app never writes power settings:
/// the Advanced page offers fixed commands to run in Terminal instead, so no
/// authorization API or privileged helper is linked.
final class PowerSettingsReader: PowerSettingsReading, @unchecked Sendable {
    private let pmsetURL = URL(fileURLWithPath: "/usr/bin/pmset")
    private let commandTimeout: TimeInterval

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

    /// Pure state check for power records left by earlier versions. Each
    /// key/source pair must match one of the allowed states; pass a single
    /// state to require an exact match.
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
