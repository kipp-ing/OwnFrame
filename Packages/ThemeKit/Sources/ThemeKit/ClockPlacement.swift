import CoreGraphics

/// Device family the clock renders on. Portable across platforms; tvOS is added
/// later (do not add it here yet).
public enum ClockIdiom: Sendable {
    case phone
    case pad
}

/// Size-constants table (points) for the clock renderer, per idiom x size.
/// Values are the source of truth from data-model.md; the renderer reads them
/// and the host tests assert the legibility floor (SC-500-08).
public enum ClockMetrics {
    /// Point size for the digits/pill numerals.
    public static func digitPointSize(idiom: ClockIdiom, size: ClockSize) -> CGFloat {
        switch (idiom, size) {
        case (.pad, .room): return 76
        case (.pad, .cozy): return 52
        case (.phone, .room): return 92
        case (.phone, .cozy): return 64
        }
    }

    /// Diameter of the analog glass face.
    public static func analogDiameter(idiom: ClockIdiom, size: ClockSize) -> CGFloat {
        switch (idiom, size) {
        case (.pad, .room): return 250
        case (.pad, .cozy): return 180
        case (.phone, .room): return 210
        case (.phone, .cozy): return 150
        }
    }
}

/// Chooses the next place for a `.random` clock. Called on photo-advance
/// boundaries (FR-510-03); time flows through `now` as a monotonic `Duration`
/// (no wall-clock dependence).
public protocol RandomPlacePicking: Sendable {
    /// Returns a new place iff `now` is >= cadence past the last relocation,
    /// never `current`, never a member of `occupied`; else returns `current`.
    mutating func place(now: Duration, current: ClockPlace?, occupied: Set<ClockPlace>) -> ClockPlace
}

/// Production `RandomPlacePicking`: relocates on a fixed cadence (default 6 min)
/// using an injected, seedable RNG so placement is deterministic in tests.
public struct RandomPlacePicker<RNG: RandomNumberGenerator & Sendable>: RandomPlacePicking {
    private var rng: RNG
    private let cadence: Duration
    private var lastRelocation: Duration?

    public init(rng: RNG, cadence: Duration = .seconds(360)) {
        self.rng = rng
        self.cadence = cadence
    }

    public mutating func place(
        now: Duration,
        current: ClockPlace?,
        occupied: Set<ClockPlace>
    ) -> ClockPlace {
        // Initial placement: no clock on screen yet. Pick immediately and record
        // the relocation time as the cadence baseline.
        guard let current else {
            let chosen = pick(avoiding: nil, occupied: occupied)
            lastRelocation = now
            return chosen
        }

        // A place exists but we have no baseline yet (e.g. restored from storage):
        // adopt `now` as the baseline and hold this cycle.
        guard let last = lastRelocation else {
            lastRelocation = now
            return current
        }

        // Relocate only once the cadence has elapsed since the last relocation.
        guard now - last >= cadence else { return current }

        let chosen = pick(avoiding: current, occupied: occupied)
        lastRelocation = now
        return chosen
    }

    private mutating func pick(avoiding current: ClockPlace?, occupied: Set<ClockPlace>) -> ClockPlace {
        var candidates = ClockPlace.fixedPlaces.filter { !occupied.contains($0) }
        if let current {
            candidates.removeAll { $0 == current }
        }
        // No free place (all fixed places occupied/excluded): stay put rather than
        // violate the constraints.
        guard let chosen = candidates.randomElement(using: &rng) else {
            return current ?? .bottomTrailing
        }
        return chosen
    }
}
