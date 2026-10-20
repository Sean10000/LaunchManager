import CryptoKit
import Foundation

struct TriggerDocumentSession {
    let url: URL?
    var root: [String: Any]
    /// Snapshot of root at open / sync time; used by `saveRoot` no-op detection.
    let openedRoot: [String: Any]
    private let openedContentHash: Data
    private let openedStableKeys: [RuleStableKey]

    var native: NativeTriggers
    var rules: [TriggerRule]
    var pathIdsInOrder: [UUID]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(root: parsed, url: url, contentHash: Self.hash(data))
    }

    /// In-memory session from a root dictionary (new agents after first build, or XML→form sync).
    init(root: [String: Any], url: URL?) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0
        )
        try self.init(root: root, url: url, contentHash: Self.hash(data))
    }

    private init(root: [String: Any], url: URL?, contentHash: Data) throws {
        self.url = url
        self.root = root
        self.openedRoot = try Self.deepCopy(root)
        self.openedContentHash = contentHash
        let parsedNative = TriggerCompiler.parseNative(from: root)
        self.native = parsedNative
        let projected = TriggerCompiler.project(parsedNative)
        self.rules = projected
        self.openedStableKeys = projected.map(Self.stableKey)
        self.pathIdsInOrder = projected.flatMap { rule in
            rule.sourceRefs.compactMap { ref -> UUID? in
                if case .watchPath(let id) = ref { return id }
                return nil
            }
        }
    }

    /// True when any rule is marked modified, or the structural rule set
    /// (kind + sourceRefs) differs from the open-time projection (add/delete/reorder).
    var triggersDirty: Bool {
        rules.contains(where: \.isModified)
            || rules.map(Self.stableKey) != openedStableKeys
    }

    /// True when `root` differs logically from the snapshot taken at open
    /// (in-place form edits or applied trigger writes).
    var rootLogicallyChanged: Bool {
        !NSDictionary(dictionary: root).isEqual(to: openedRoot)
    }

    /// Always `false` when there is no on-disk URL (in-memory / new agent).
    func fileChangedOnDisk() throws -> Bool {
        guard let url else { return false }
        let data = try Data(contentsOf: url)
        return Self.hash(data) != openedContentHash
    }

    mutating func applyTriggerRulesToRoot() {
        root = TriggerCompiler.applyTriggers(
            to: root,
            native: native,
            rules: rules,
            pathIdsInOrder: pathIdsInOrder
        )
    }

    static func hash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    // MARK: - Private

    private struct RuleStableKey: Equatable {
        let kind: TriggerRuleKind
        let sourceRefs: [SourceRef]
    }

    private static func stableKey(_ rule: TriggerRule) -> RuleStableKey {
        RuleStableKey(kind: rule.kind, sourceRefs: rule.sourceRefs)
    }

    private static func deepCopy(_ dict: [String: Any]) throws -> [String: Any] {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dict, format: .binary, options: 0
        )
        guard let copy = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return copy
    }
}
