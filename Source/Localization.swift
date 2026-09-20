import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Codable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        let first = preferredLanguages.first?.lowercased() ?? ""
        return first.hasPrefix("zh-hans") || first == "zh-cn" || first == "zh-sg"
            ? .simplifiedChinese : .english
    }

    var nativeName: String {
        switch self {
        case .system: return "跟随系统 / Follow System"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }
}

/// Immutable, language-independent display data. No executor reads mutable UI
/// language state. String arguments are verbatim; nested messages stay deferred.
struct LocalizedText: Equatable, Comparable, Codable, ExpressibleByStringLiteral,
    ExpressibleByStringInterpolation {
    indirect enum Part: Equatable, Codable {
        case message(key: String, fallback: String, arguments: [Part])
        case verbatim(String)
        case integer(Int)
        case decimal(Double)
        case sequence([Part])
    }

    let part: Part

    init(part: Part) { self.part = part }
    init(verbatim value: String) { part = .verbatim(value) }
    init(stringLiteral value: String) {
        part = .message(key: Self.key(for: value), fallback: value, arguments: [])
    }
    init(stringInterpolation: StringInterpolation) {
        part = .message(key: Self.key(for: stringInterpolation.template),
                        fallback: stringInterpolation.template,
                        arguments: stringInterpolation.arguments)
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var template = ""
        var arguments: [Part] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { template += literal }
        mutating func appendInterpolation(_ value: LocalizedText) { append(value.part) }
        mutating func appendInterpolation(_ value: String) { append(.verbatim(value)) }
        mutating func appendInterpolation(_ value: Int) { append(.integer(value)) }
        mutating func appendInterpolation(_ value: Double) { append(.decimal(value)) }
        mutating func appendInterpolation<T>(_ value: T) { append(.verbatim(String(describing: value))) }
        private mutating func append(_ part: Part) {
            template += "{\(arguments.count)}"
            arguments.append(part)
        }
    }

    /// Stable FNV-1a keys are generated from templates, never translated text.
    static func key(for template: String) -> String {
        let hash = template.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        return "text." + String(hash, radix: 16)
    }

    func rendered(language: AppLanguage, resources: LocalizationResources = .main,
                  region: Locale = .autoupdatingCurrent) -> String {
        func render(_ part: Part) -> String {
            switch part {
            case .verbatim(let value): return value
            case .integer(let value): return String(value)
            case .decimal(let value):
                return String(format: "%.15g", locale: region, value)
            case .sequence(let parts): return parts.map(render).joined()
            case .message(let key, let fallback, let arguments):
                let template = resources.string(key: key, language: language) ?? fallback
                // Replace tokens in one pass: verbatim arguments must never be
                // interpreted again as placeholders or localization keys.
                let expression = try! NSRegularExpression(pattern: "\\{([0-9]+)\\}")
                let ns = template as NSString
                var result = "", cursor = 0
                for match in expression.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
                    result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                    let index = Int(ns.substring(with: match.range(at: 1)))!
                    result += arguments.indices.contains(index) ? render(arguments[index]) : ns.substring(with: match.range)
                    cursor = match.range.location + match.range.length
                }
                return result + ns.substring(from: cursor)
            }
        }
        return render(part)
    }

    var isEmpty: Bool { source.isEmpty }
    /// Deterministic source projection for legacy Chinese contracts, not UI.
    var source: String { rendered(language: .simplifiedChinese, resources: .empty) }
    func contains(_ value: String) -> Bool { source.contains(value) }
    static func < (lhs: LocalizedText, rhs: LocalizedText) -> Bool { lhs.source < rhs.source }

    func isKnown(to resources: LocalizationResources) -> Bool {
        func check(_ part: Part, depth: Int) -> Bool {
            guard depth < 32 else { return false }
            switch part {
            case .verbatim, .integer, .decimal: return true
            case .sequence(let parts): return parts.count < 256 && parts.allSatisfy { check($0, depth: depth + 1) }
            case .message(let key, let fallback, let arguments):
                return key == Self.key(for: fallback) &&
                    resources.string(key: key, language: .english) != nil &&
                    arguments.count < 64 && arguments.allSatisfy { check($0, depth: depth + 1) }
            }
        }
        return check(part, depth: 0)
    }

    static func + (lhs: LocalizedText, rhs: LocalizedText) -> LocalizedText {
        LocalizedText(part: .sequence([lhs.part, rhs.part]))
    }
    static func + (lhs: LocalizedText, rhs: String) -> LocalizedText { lhs + LocalizedText(verbatim: rhs) }
    static func + (lhs: String, rhs: LocalizedText) -> LocalizedText { LocalizedText(verbatim: lhs) + rhs }
    static func += (lhs: inout LocalizedText, rhs: LocalizedText) { lhs = lhs + rhs }
}

func L(_ text: LocalizedText) -> LocalizedText { text }

extension Array where Element == LocalizedText {
    func joined(separator: LocalizedText = "") -> LocalizedText {
        var parts: [LocalizedText.Part] = []
        for (index, value) in enumerated() {
            if index > 0 { parts.append(separator.part) }
            parts.append(value.part)
        }
        return LocalizedText(part: .sequence(parts))
    }
}

struct LocalizationResources {
    private let tables: [AppLanguage: [String: String]]
    static let main = LocalizationResources(bundle: .main)
    static let empty = LocalizationResources(tables: [:])
    private init(tables: [AppLanguage: [String: String]]) { self.tables = tables }

    init(bundle: Bundle) {
        var tables: [AppLanguage: [String: String]] = [:]
        for language in [AppLanguage.english, .simplifiedChinese] {
            guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil,
                                         forLocalization: language.rawValue),
                  let data = FileManager.default.contents(atPath: path),
                  let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            else { continue }
            tables[language] = table
        }
        self.tables = tables
    }

    func string(key: String, language: AppLanguage) -> String? {
        tables[language.resolved()]?[key] ?? tables[.english]?[key]
    }
    func keys(for language: AppLanguage) -> Set<String> { Set(tables[language]?.keys.map { $0 } ?? []) }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let preferenceKey = "interfaceLanguage.v1"
    @Published private(set) var choice: AppLanguage
    @Published private(set) var resolved: AppLanguage
    let resources: LocalizationResources
    private let state: any ApplicationStateStoring
    private let preferredLanguages: () -> [String]

    init(state: any ApplicationStateStoring = UserDefaults.standard,
         resources: LocalizationResources = .main,
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.state = state
        self.resources = resources
        self.preferredLanguages = preferredLanguages
        let initial = AppLanguage(rawValue: state.object(forKey: Self.preferenceKey) as? String ?? "") ?? .system
        choice = initial
        resolved = initial.resolved(preferredLanguages: preferredLanguages())
    }

    func select(_ language: AppLanguage) {
        guard language != choice else { return }
        choice = language
        resolved = language.resolved(preferredLanguages: preferredLanguages())
        state.set(language.rawValue, forKey: Self.preferenceKey)
    }
    func refreshSystemLanguage() {
        let value = choice.resolved(preferredLanguages: preferredLanguages())
        if resolved != value { resolved = value }
    }
    func text(_ value: LocalizedText) -> String { value.rendered(language: resolved, resources: resources) }
    func text(_ value: String) -> String { value }
}

protocol DisplayMessageError: Error { var displayMessage: LocalizedText { get } }
extension Error {
    var displayMessage: LocalizedText {
        (self as? any DisplayMessageError)?.displayMessage ?? LocalizedText(verbatim: localizedDescription)
    }
}

enum RegionalNumberInput {
    static func parse(_ text: String, region: Locale = .autoupdatingCurrent) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let separator = region.decimalSeparator ?? "."
        return Double(separator == "." ? trimmed : trimmed.replacingOccurrences(of: separator, with: "."))
    }
}
