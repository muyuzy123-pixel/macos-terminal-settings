import Foundation

/// System-facing dependencies are deliberately expressed as small protocols.
/// Production uses the concrete adapters below; contract tests can inject
/// recording or fail-closed implementations without touching real settings.
protocol PreferenceExecuting: AnyObject, Sendable {
    func snapshots(for addresses: [PreferenceAddress]) throws -> [PreferenceSnapshot]
    func verify(_ expected: [PreferenceSnapshot]) throws
    func ensureUnchanged(since expected: [PreferenceSnapshot]) throws
    func ensureCurrentMatchesAny(
        _ allowedStates: [[PreferenceSnapshot]],
        operation: LocalizedText
    ) throws
    func readValues(
        for addresses: [PreferenceAddress]
    ) throws -> [PreferenceAddress: PreferenceValue]
    func apply(_ mutation: PreferenceMutation) throws
    func restore(_ snapshots: [PreferenceSnapshot]) throws
    func restorePreservingExternalChanges(
        _ target: [PreferenceSnapshot],
        whenCurrentMatches allowedStates: [[PreferenceSnapshot]]
    ) throws -> [PreferenceAddress]
}

protocol ProcessRestarting: AnyObject, Sendable {
    func restart(_ processNames: [String])
}

protocol PreferenceManagementProviding: Sendable {
    func forcedAddresses(
        for addresses: [PreferenceAddress]
    ) throws -> Set<PreferenceAddress>
}

struct SystemPreferenceManagementProvider: PreferenceManagementProviding {
    func forcedAddresses(
        for addresses: [PreferenceAddress]
    ) throws -> Set<PreferenceAddress> {
        Set(addresses.filter { address in
            UserDefaults.standard.objectIsForced(
                forKey: address.key,
                inDomain: address.domain
            )
        })
    }
}

/// Reads the allow-listed power settings. Nothing in the app writes them.
protocol PowerSettingsReading: AnyObject, Sendable {
    func snapshots(for keys: [String]) throws -> [PowerSettingSnapshot]
}

protocol PreferenceTransactionJournaling: Sendable {
    func persist(_ record: UndoRecord, to url: URL) throws
    func read(from url: URL) throws -> UndoRecord?
    @discardableResult func remove(at url: URL) -> Bool
}

struct FilePreferenceTransactionJournal: PreferenceTransactionJournaling {
    func persist(_ record: UndoRecord, to url: URL) throws {
        guard PersistedRecordPolicy.isAllowed(record) else {
            throw PreferenceExecutorError.verification(
                L("拒绝写入目录白名单之外的恢复记录")
            )
        }
        try PreferenceTransactionJournal.write(record, to: url)
    }

    func read(from url: URL) throws -> UndoRecord? {
        try PreferenceTransactionJournal.load(from: url)
    }

    @discardableResult
    func remove(at url: URL) -> Bool {
        PreferenceTransactionJournal.clear(url)
    }
}

/// Only application-owned draft and recovery metadata flows through this
/// boundary. It never represents a macOS preference domain.
protocol ApplicationStateStoring: AnyObject {
    func bool(forKey defaultName: String) -> Bool
    func dictionary(forKey defaultName: String) -> [String: Any]?
    func object(forKey defaultName: String) -> Any?
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: ApplicationStateStoring {}

protocol TimeProviding: Sendable {
    func now() -> Date
}

struct SystemTimeProvider: TimeProviding {
    func now() -> Date { Date() }
}

protocol IdentifierProviding: Sendable {
    func makeIdentifier() -> UUID
}

struct SystemIdentifierProvider: IdentifierProviding {
    func makeIdentifier() -> UUID { UUID() }
}
