import Foundation

// DEBUG-only by design — see the note in StubStoreClient.swift. A launch argument that grants
// entitlements must not be compiled into a shipping build, even unreachably.
#if DEBUG

/// Launch-argument seams that let UI tests drive the purchase gate hermetically
/// (contracts/uitest-seams.md). Shared by both app targets so the iOS and tvOS surfaces
/// answer to exactly the same flags.
///
/// Nothing here is reachable in a normal launch: the app only consults these when the
/// process was started with the corresponding `--uitest-*` argument.
public enum PurchaseUITestSeams {

    /// Entitlements requested by `--uitest-entitlements=<list>`, comma-separated over
    /// `none`/`pro`/`automation`/`all`.
    ///
    /// An absent flag yields the free tier — deliberately identical to `none`, so the
    /// default hermetic launch exercises the ungated frame. Unrecognised words are ignored
    /// rather than fatal, so a typo in a test degrades to "free" instead of crashing.
    public static var entitlements: EntitlementSet { entitlements() }

    /// Argument-injectable form of ``entitlements``, so the parse is testable without a
    /// relaunch. Production callers use the no-argument property above.
    public static func entitlements(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> EntitlementSet {
        guard let arg = arguments
            .first(where: { $0.hasPrefix("--uitest-entitlements=") })
        else { return EntitlementSet.none }

        let words = arg.dropFirst("--uitest-entitlements=".count).split(separator: ",")
        return words.reduce(into: EntitlementSet.none) { set, word in
            switch word {
            case "all": set = EntitlementSet.all
            case "pro": set.insert(.pro)
            case "automation": set.insert(.automation)
            default: break // includes "none"
            }
        }
    }

    /// Whether this launch explicitly asked for an entitlement set.
    ///
    /// Distinct from ``entitlements`` returning `.none`, and deliberately so: an absent flag and
    /// `--uitest-entitlements=none` yield the same `EntitlementSet`, but only the second is an
    /// *override*. A caller choosing between "seed entitlements" and "ask the real store"
    /// therefore cannot decide on the value alone — it has to ask whether the flag was present.
    ///
    /// The production launch path consults this so a device test rig can seed entitlements
    /// **without** entering the hermetic `--uitest` world. That matters because the hermetic
    /// branch wires no MQTT broker at all (`makeCoordinator` returns nil there), so it can never
    /// exercise the HA gating contract (FR-1100-03a) against a real broker on real hardware —
    /// which is the one thing a physical frame is uniquely able to prove.
    ///
    /// A bare `--uitest-entitlements` with no `=` is a typo rather than a request, and is not
    /// treated as an override: failing that case toward production keeps a mistyped flag from
    /// silently swapping a real frame's StoreKit store for a stub that grants nothing.
    public static func hasEntitlementOverride(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains { $0.hasPrefix("--uitest-entitlements=") }
    }

    /// The store condition modelled by `--uitest-store=<stub|unavailable|pending>`.
    /// Defaults to `.stub` so a launch that only seeds entitlements still has a working
    /// purchase path.
    public static var storeBehavior: StubStoreClient.Behavior {
        guard let arg = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--uitest-store=") }),
              let behavior = StubStoreClient.Behavior(
                  rawValue: String(arg.dropFirst("--uitest-store=".count))
              )
        else { return .stub }
        return behavior
    }

    /// A fully hermetic entitlement store.
    ///
    /// The seeded set is written into a throwaway defaults suite and read back through the
    /// real ``EntitlementSnapshotCache``, so a UI test exercises the same load path
    /// production uses rather than a bypass. StoreKit is never touched.
    ///
    /// The suite name is unique per launch, so one test's entitlements can never leak into
    /// the next, and `UserDefaults.standard` is left untouched.
    @MainActor
    public static func makeStore() -> EntitlementStore {
        let seeded = entitlements
        let defaults = UserDefaults(suiteName: "uitest.entitlements.\(UUID().uuidString)")
            ?? .standard
        let cache = EntitlementSnapshotCache(defaults: defaults)
        cache.save(EntitlementSnapshot(entitlements: seeded, savedAt: Date()))
        // The stub store starts out owning exactly what was seeded, so a Restore inside a
        // test repopulates the same set instead of wiping it.
        let owned = Set(ProductCatalog.unlocks.filter {
            ProductCatalog.grants($0).isSubset(of: seeded)
        })
        return EntitlementStore(
            client: StubStoreClient(behavior: storeBehavior, owned: owned),
            cache: cache
        )
    }
}

#endif
