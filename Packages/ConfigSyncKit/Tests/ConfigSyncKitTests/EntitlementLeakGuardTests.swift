import Foundation
import Testing
@testable import ConfigSyncKit

// MARK: - Why this file exists
//
// Feature 1100 (purchase gate), spec edge case "entitlement state vs. config sync" and
// data-model invariant "Entitlement types never appear in `ConfigSyncKit` payload models".
//
// Purchases belong to the *Apple ID*, and every device derives its own entitlements from
// StoreKit / Family Sharing. Mirroring entitlement state through our own KVS or CloudKit
// channel would be wrong twice over: it would duplicate a source of truth we do not own, and
// it would hand anyone who can write a sync payload a way to spoof paid features onto an
// unentitled device.
//
// **This suite is expected to be GREEN on arrival — nothing syncs entitlement state today, and
// that is precisely the point.** It is a negative regression guard, not a spec for new work: it
// pins the current, correct behaviour so that a future change to the sync payloads cannot
// quietly start leaking purchase state. If this file ever goes red, the fix is almost never in
// the test — it is that a payload type grew a field it must not have.
//
// Two channels carry payloads out of this module, and both are covered:
//
//   1. Non-secret, iCloud key-value storage — `SyncedConfig`, serialized either as JSON
//      (`Codable`) or as the flat `[String: KVSValue]` layout produced by
//      `SyncedConfigKVSCodec` / `UbiquitousKVSConfigSyncStore`.
//   2. Secret, CloudKit private-database encrypted fields — `SyncedSecret`, written field by
//      field by `CloudKitSecretSyncStore.apply(_:to:)`.
//
// How the payload list was enumerated (so none is missed): the two store protocols each take
// exactly one payload type — `ConfigSyncStore.save(_ config: SyncedConfig)` and
// `SecretSyncStore.publish(_ secret: SyncedSecret)` — so the pair above is closed by
// construction. Everything else in `Sources/ConfigSyncKit/` is behaviour or plumbing that
// serializes nothing of its own: `ConfigPublisher`, `ConfigConsumer`, `SecretWriting`,
// `SecretSyncStoreFactory`, the store adapters, `KVSValue` (a value wrapper with no field
// names) and `ConfigSyncSchema` (a constant). To keep that claim honest as the module grows,
// `payloadTypeInventoryIsStillClosed` below re-derives the set of `Codable` declarations from
// the source directory at test time and fails when a new one appears unreviewed.
//
// Note for future maintainers: `SecretSyncStoreFactory.cloudKitEntitlementsPresent` contains
// the word "entitlement", but it means the *CloudKit container entitlement* — an app-target
// capability, nothing to do with purchases. It is not an encoded key, so it is correctly out of
// scope here. Do not "fix" this suite by widening it into a source-text grep for "entitlement".

@Suite
struct EntitlementLeakGuardTests {

    // MARK: - Fixtures

    /// Every non-secret field populated, so no field can be skipped by being `nil` at encode time.
    private func fullyPopulatedConfig() -> SyncedConfig {
        SyncedConfig(
            schema: ConfigSyncSchema.current,
            baseURL: URL(string: "https://immich.example.com"),
            sourceLibrary: Data(#"{"active":"shared-link"}"#.utf8),
            theme: Data(#"{"transition":"fade","kenBurns":true}"#.utf8),
            cacheBudgetBytes: 512_000_000,
            haPublish: Data(#"{"publishImage":true}"#.utf8),
            brokerHost: "broker.local",
            brokerPort: 8883
        )
    }

    /// Every secret field populated, with realistic `Source.id` keys in the password map.
    private func fullyPopulatedSecret() -> SyncedSecret {
        SyncedSecret(
            immichApiKey: "immich-api-key-value",
            mqttCredentials: Data(#"{"username":"frame","password":"hunter2"}"#.utf8),
            sharedLinkPasswords: [
                "9E1D0B1E-0F2A-4C77-9E2B-1C0A5B3D7E44": "link-password",
                "1B7C4A02-5D66-4F31-8A19-6D2E9F0C3B58": "other-link-password",
            ]
        )
    }

    // MARK: - Non-secret channel: SyncedConfig as JSON

    /// The `Codable` (JSON) representation of the non-secret payload names nothing purchase-related.
    ///
    /// Asserted against the *encoded output* rather than a hand-written `CodingKeys` list: a
    /// hand-copied list rots the moment someone adds a stored property, whereas the encoder
    /// always tells the truth about what actually goes over the wire.
    @Test
    func syncedConfigJSONCarriesNoEntitlementKeys() throws {
        let encoded = try JSONEncoder().encode(fullyPopulatedConfig())
        let keys = try EntitlementLexicon.keys(inJSON: encoded)

        // Sanity: the collector really saw a populated payload (guards against a vacuous pass
        // if encoding ever produced an empty object).
        #expect(keys.contains("schema"))
        #expect(keys.count >= 8, "expected every populated field to appear; got \(keys.sorted())")

        expectNoEntitlementTerms(in: keys, channel: "SyncedConfig JSON")
    }

    // MARK: - Non-secret channel: SyncedConfig as it lands in iCloud KVS

    /// The flat KVS layout — the representation that actually reaches iCloud key-value storage —
    /// names nothing purchase-related either.
    @Test
    func syncedConfigKVSLayoutCarriesNoEntitlementKeys() {
        let store = InMemoryConfigSyncStore()
        store.save(fullyPopulatedConfig())

        let keys = Set(store.backingStore().keys)

        #expect(keys.count >= 8, "expected one KVS key per populated field; got \(keys.sorted())")
        expectNoEntitlementTerms(in: keys, channel: "SyncedConfig KVS layout")
    }

    // MARK: - Secret channel: SyncedSecret as CloudKit encrypted fields

    /// The CloudKit encrypted-field layout names nothing purchase-related.
    ///
    /// `SyncedSecret` is not `Codable`; `CloudKitSecretSyncStore.apply(_:to:)` writes one
    /// `record.encryptedValues[...]` entry per stored property, using the property's own name.
    /// Instantiating that store here is impossible (`CKContainer.default()` traps without the
    /// container entitlement — see `SecretSyncStoreFactory`), so the field layout is re-derived
    /// by reflection over the payload, which is the same 1:1 mapping the adapter performs and,
    /// like the encoder above, cannot drift out of date when a property is added.
    ///
    /// The `sharedLinkPasswords` map is a *dynamic* key space (`Source.id` values chosen at
    /// runtime, not schema), so only its field name is checked here — the inertness of hostile
    /// keys inside it is asserted separately by `entitlementShapedSharedLinkKeyStaysInertData`.
    @Test
    func syncedSecretCloudKitFieldLayoutCarriesNoEntitlementKeys() {
        let fields = Mirror(reflecting: fullyPopulatedSecret()).children.compactMap(\.label)
        let keys = Set(fields)

        #expect(
            keys == ["immichApiKey", "mqttCredentials", "sharedLinkPasswords"],
            """
            The CloudKit secret field layout changed. Re-read \
            CloudKitSecretSyncStore.apply(_:to:) and confirm the new field is not \
            entitlement-derived before updating this expectation. Got: \(keys.sorted())
            """
        )
        expectNoEntitlementTerms(in: keys, channel: "SyncedSecret CloudKit fields")
    }

    // MARK: - Reverse direction: a hostile payload cannot inject entitlements

    /// A JSON snapshot carrying extra entitlement-ish keys decodes to exactly the same
    /// `SyncedConfig` as the clean snapshot — the extra keys contribute nothing, and re-encoding
    /// the result does not smuggle them onward.
    ///
    /// This is the spoofing case from the spec: a payload written by an entitled (or malicious)
    /// device must not unlock anything on the device that reads it.
    @Test
    func hostileJSONPayloadCannotInjectEntitlements() throws {
        let clean = Data(#"{"schema":1,"brokerHost":"broker.local","brokerPort":8883}"#.utf8)
        let hostile = Data(
            """
            {"schema":1,"brokerHost":"broker.local","brokerPort":8883,\
            "entitlements":["supporter"],"isSupporter":true,"unlocked":true,\
            "purchase":{"productID":"ing.kipp.Immich-Slideshow.unlock.supporter","owned":true},\
            "storeKitTransactions":[{"receipt":"forged"}]}
            """.utf8
        )

        let decodedClean = try JSONDecoder().decode(SyncedConfig.self, from: clean)
        let decodedHostile = try JSONDecoder().decode(SyncedConfig.self, from: hostile)

        // The unexpected keys are dropped on the floor, not stored anywhere.
        #expect(decodedHostile == decodedClean)

        // Nothing entitlement-shaped survived into the model...
        let labels = Set(Mirror(reflecting: decodedHostile).children.compactMap(\.label))
        expectNoEntitlementTerms(in: labels, channel: "SyncedConfig decoded from hostile JSON")

        // ...nor into what this device would publish onward.
        let reEncoded = try JSONEncoder().encode(decodedHostile)
        let reEncodedKeys = try EntitlementLexicon.keys(inJSON: reEncoded)
        expectNoEntitlementTerms(in: reEncodedKeys, channel: "SyncedConfig re-encoded")
    }

    /// The same injection attempt through the KVS channel: unknown backing keys are ignored by
    /// the codec and cannot reach the decoded snapshot.
    @Test
    func hostileKVSBackingCannotInjectEntitlements() {
        let clean: [String: KVSValue] = [
            "cfg.schema": .int64(1),
            "cfg.brokerHost": .string("broker.local"),
        ]
        var hostile = clean
        hostile["cfg.entitlements"] = .string("supporter")
        hostile["cfg.unlock.pro"] = .int64(1)  // superseded product id — still an attack shape
        hostile["ing.kipp.Immich-Slideshow.unlock.supporter"] = .int64(1)

        let decodedClean = SyncedConfigKVSCodec.decode(clean)
        let decodedHostile = SyncedConfigKVSCodec.decode(hostile)

        #expect(decodedHostile == decodedClean)
        #expect(decodedHostile != nil)

        // Re-encoding drops the injected keys entirely — they never round-trip back to iCloud.
        let reEncoded = SyncedConfigKVSCodec.encode(decodedHostile ?? SyncedConfig())
        expectNoEntitlementTerms(in: Set(reEncoded.keys), channel: "SyncedConfig re-encoded to KVS")
    }

    /// A shared-link password keyed to look exactly like a purchase product id stays what it is:
    /// an opaque per-source password. It is routed only to `writeSharedLinkPassword` and can
    /// never become an entitlement, because the consumer has no entitlement sink to route it to.
    @Test
    func entitlementShapedSharedLinkKeyStaysInertData() async {
        let hostileKey = "ing.kipp.Immich-Slideshow.unlock.supporter"
        let secretStore = InMemorySecretSyncStore(
            stored: SyncedSecret(
                immichApiKey: "immich-api-key-value",
                sharedLinkPasswords: [hostileKey: "not-an-entitlement"]
            )
        )
        let consumer = ConfigConsumer(configStore: InMemoryConfigSyncStore(), secretStore: secretStore)
        let writer = RecordingSecretWriter()

        let result = await consumer.hydrateSecrets(into: writer)

        #expect(result == .hydrated)
        #expect(await writer.sharedLinkPasswords == [hostileKey: "not-an-entitlement"])
        #expect(await writer.immichApiKey == "immich-api-key-value")
        #expect(await writer.mqttCredentials == nil)
    }

    // MARK: - The guard's own machinery

    /// The key collector recurses: a leak nested inside an object or an array must be found.
    ///
    /// Today's payloads are flat (their sub-configurations are opaque, already-encoded `Data`
    /// blobs owned by other packages), so without this test the recursion above would be
    /// untested scaffolding — and would silently stop protecting anything the day a payload
    /// grows a typed nested model.
    @Test
    func keyCollectorRecursesIntoNestedContainersAndArrays() throws {
        let nested = Data(
            """
            {"outer":{"middle":[{"deep":{"entitlements":["pro"]}}]},"sibling":1}
            """.utf8
        )

        let keys = try EntitlementLexicon.keys(inJSON: nested)

        #expect(keys == ["outer", "middle", "deep", "entitlements", "sibling"])
        #expect(!EntitlementLexicon.offendingTerms(in: keys).isEmpty)
    }

    /// The matcher fires on real leaks and stays silent on innocent names.
    ///
    /// Word-boundary matching, not `contains`: the required term list includes `pro` and `tip`,
    /// and a naive substring check would condemn "provider", "profile", "protocol" and even
    /// "mul-tip-le". A guard that fails on an innocent rename gets deleted by the next
    /// maintainer, which is strictly worse than no guard at all. So each key is split into
    /// lowercased words at camelCase and punctuation boundaries, and a term must match a whole
    /// word — or a run of adjacent words, so that "storeKit" still matches "storekit" — allowing
    /// only the inflections s/es/ed/ing (plus "d" for terms ending in "e", so that "purchased"
    /// is caught while "prodURL" stays clear of "pro"). The product-id prefix is matched as a
    /// plain substring instead, since a literal that specific cannot appear innocently.
    @Test
    func matcherCatchesLeaksWithoutCondemningInnocentNames() {
        let leaks = [
            "entitlements", "entitlementSet", "purchase", "purchaseState", "purchased",
            "unlock", "unlockedTiers", "isPro", "proTier", "automation", "automationUnlocked",
            // The current unlock's vocabulary — caught by the "supporter" term, not only by "unlock".
            "isSupporter", "supporterTier", "supporterUnlocked",
            "storeKit", "storekitTransactions", "transaction", "receipt", "receipts",
            "tip", "tipJar", "cfg.entitlements",
            "ing.kipp.Immich-Slideshow.unlock.supporter",
        ]
        for key in leaks {
            #expect(
                !EntitlementLexicon.offendingTerms(in: [key]).isEmpty,
                "matcher missed the entitlement leak '\(key)'"
            )
        }

        let innocent = [
            // Today's real payload keys, both channels.
            "schema", "baseURL", "sourceLibrary", "theme", "cacheBudgetBytes", "haPublish",
            "brokerHost", "brokerPort", "cfg.schema", "cfg.baseURL", "cfg.cacheBudgetBytes",
            "immichApiKey", "mqttCredentials", "sharedLinkPasswords",
            // Plausible future names that merely contain a forbidden term as a substring.
            "provider", "profile", "protocol", "properties", "progress", "prodURL",
            "multipleSources", "description", "relative", "base",
        ]
        for key in innocent {
            #expect(
                EntitlementLexicon.offendingTerms(in: [key]).isEmpty,
                "matcher wrongly condemned the innocent key '\(key)'"
            )
        }
    }

    /// The payload inventory this suite covers is still complete.
    ///
    /// Re-derived from the source directory rather than asserted from memory: if someone adds a
    /// third `Codable` payload to the module, this fails and forces them to extend the guard
    /// above instead of quietly shipping an uncovered channel.
    ///
    /// - Note: The pattern matches conformance on the *declaration* line. A payload that gained
    ///   `Codable` via `extension Foo: Codable` would slip past it. That is acceptable today only
    ///   because no first-party source in this repo uses extension-based conformance (checked
    ///   2026-07-19) — if that idiom ever appears here, widen the pattern rather than trusting
    ///   this test.
    @Test
    func payloadTypeInventoryIsStillClosed() throws {
        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ConfigSyncKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("ConfigSyncKit", isDirectory: true)

        let files = try FileManager.default
            .contentsOfDirectory(at: sourcesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        // Fail loudly rather than pass vacuously if the layout ever moves.
        #expect(files.count >= 8, "expected to scan the ConfigSyncKit sources at \(sourcesDirectory.path)")

        let declaration = try NSRegularExpression(
            pattern: #"^\s*(?:public\s+|internal\s+|final\s+)*(?:struct|class|enum)\s+([A-Za-z_]\w*)[^{\n]*\b(?:Codable|Encodable|Decodable)\b"#,
            options: [.anchorsMatchLines]
        )

        var codableTypes: Set<String> = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in declaration.matches(in: source, range: range) {
                if let nameRange = Range(match.range(at: 1), in: source) {
                    codableTypes.insert(String(source[nameRange]))
                }
            }
        }

        #expect(
            codableTypes == ["SyncedConfig"],
            """
            A new Codable payload appeared in ConfigSyncKit: \(codableTypes.sorted()). \
            Extend EntitlementLeakGuardTests to cover its encoded keys before updating this \
            expectation — an uncovered payload is an uncovered entitlement-leak path.
            """
        )
    }

    // MARK: - Shared assertion

    private func expectNoEntitlementTerms(
        in keys: Set<String>,
        channel: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let offenders = EntitlementLexicon.offendingTerms(in: keys)
        #expect(
            offenders.isEmpty,
            """
            Entitlement/purchase state leaked into the \(channel) sync payload. \
            Offending keys: \(offenders.map { "\($0.key) (matched '\($0.term)')" }.sorted().joined(separator: ", ")). \
            Config sync must never carry purchase state — each device derives its entitlements \
            from its own store account (spec 1100, edge case "entitlement state vs. config sync").
            """,
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - Entitlement vocabulary + key matching

/// Word-boundary matcher for entitlement/purchase vocabulary in encoded payload keys.
///
/// See `matcherCatchesLeaksWithoutCondemningInnocentNames` for the rationale behind
/// word-boundary matching over naive `contains`.
private enum EntitlementLexicon {

    /// Terms that must never name a key in a sync payload.
    ///
    /// "supporter" is the current unlock's distinctive word; "pro" and "automation" are the
    /// superseded tier names, kept as defense-in-depth so a stray legacy key is still caught.
    static let forbiddenTerms: Set<String> = [
        "entitlement", "entitled", "purchase", "unlock", "supporter", "pro", "automation",
        "storekit", "transaction", "receipt", "tip",
    ]

    /// Inflections a forbidden term may legitimately wear.
    ///
    /// Bare "d" is excluded — it would make "prod" (production) match "pro" — and reinstated
    /// only for terms already ending in "e", which is how English forms their past tense:
    /// "purchase" → "purchased", never "pro" → "prod".
    static func inflections(for term: String) -> [String] {
        let base = ["", "s", "es", "ed", "ing"]
        return term.hasSuffix("e") ? base + ["d"] : base
    }

    /// The purchase product-id prefix. Specific enough to match as a plain substring.
    static let productIDPrefix = "ing.kipp.immich-slideshow.unlock"

    /// Every key in an encoded JSON payload, recursing into nested objects and arrays.
    static func keys(inJSON data: Data) throws -> Set<String> {
        var found: Set<String> = []
        collect(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]), into: &found)
        return found
    }

    private static func collect(_ node: Any, into found: inout Set<String>) {
        switch node {
        case let object as [String: Any]:
            for (key, value) in object {
                found.insert(key)
                collect(value, into: &found)
            }
        case let array as [Any]:
            for element in array { collect(element, into: &found) }
        default:
            break  // scalars carry no key names
        }
    }

    /// Keys that name entitlement/purchase state, paired with the term that matched.
    static func offendingTerms(in keys: Set<String>) -> [(key: String, term: String)] {
        keys.compactMap { key in
            guard let term = matchedTerm(in: key) else { return nil }
            return (key, term)
        }
    }

    private static func matchedTerm(in key: String) -> String? {
        if key.lowercased().contains(productIDPrefix) { return productIDPrefix }

        // Split the key as written — lowercasing first would erase the camelCase boundaries
        // that "isPro" and "storeKitTransactions" depend on. `words(of:)` lowercases per
        // character instead.
        let candidates = wordRuns(of: key)
        for term in forbiddenTerms.sorted() {
            for inflection in inflections(for: term) where candidates.contains(term + inflection) {
                return term
            }
        }
        return nil
    }

    /// Every run of 1...3 adjacent words in the key. Runs (not just single words) so that a
    /// camelCased "storeKit" still matches the single-word term "storekit".
    private static func wordRuns(of key: String) -> Set<String> {
        let words = self.words(of: key)
        var runs: Set<String> = []
        for start in words.indices {
            for end in start..<min(start + 3, words.count) {
                runs.insert(words[start...end].joined())
            }
        }
        return runs
    }

    /// Split into lowercased words at camelCase and punctuation boundaries, keeping acronym
    /// runs (URL) together.
    private static func words(of key: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasUppercase = false

        for character in key {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current); current = "" }
                previousWasUppercase = false
                continue
            }
            let isUppercase = character.isUppercase
            if isUppercase, !previousWasUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(contentsOf: character.lowercased())
            previousWasUppercase = isUppercase
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

// MARK: - Fake

/// Records what a consumer writes into the keychain, so hostile payload values can be shown to
/// land only in the sinks that exist — none of which is an entitlement.
private actor RecordingSecretWriter: SecretWriting {
    private(set) var immichApiKey: String?
    private(set) var mqttCredentials: Data?
    private(set) var sharedLinkPasswords: [String: String] = [:]

    func writeImmichApiKey(_ apiKey: String) async { immichApiKey = apiKey }
    func writeMqttCredentials(_ credentials: Data) async { mqttCredentials = credentials }
    func writeSharedLinkPassword(_ password: String, forSourceID sourceID: String) async {
        sharedLinkPasswords[sourceID] = password
    }
}
