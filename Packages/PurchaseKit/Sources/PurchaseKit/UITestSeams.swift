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
    public static var entitlements: EntitlementSet {
        guard let arg = ProcessInfo.processInfo.arguments
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
