//
//  FrameIntents.swift
//  Immich Slideshow
//
//  800 (T014): the five US1 AppIntent shells — one-call thin over
//  FrameCommandService, resolved through FrameIntentContext (the documented
//  composition seam; see that file for why not AppDependencyManager). All logic,
//  validation, and parity live in AppIntentsKit where they are host-tested;
//  nothing here may grow beyond resolve → forward → map the error.
//

import AppIntents
import AppIntentsKit

/// The contract's user-facing error copy (English-only, FR-300-30), mapped 1:1
/// from the package's closed taxonomy. Parameter details (like the rejected
/// percent) stay out of the copy by design — the message names the rule.
enum FrameIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notConfigured
    case frameNotOpen
    case brightnessOutOfRange
    case sourceMissing

    init(_ error: FrameCommandError) {
        switch error {
        case .notConfigured: self = .notConfigured
        case .frameNotOpen: self = .frameNotOpen
        case .brightnessOutOfRange: self = .brightnessOutOfRange
        case .sourceMissing: self = .sourceMissing
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConfigured:
            return "Set up the frame first — open Photo Frame and add a source."
        case .frameNotOpen:
            return "Photo Frame must be open on the frame device for this."
        case .brightnessOutOfRange:
            return "Brightness must be between 0 and 100 percent."
        case .sourceMissing:
            return "This source no longer exists in the frame's library."
        }
    }
}

struct PauseSlideshowIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Slideshow"
    static let description = IntentDescription("Pauses the photo frame's slideshow.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let registry = try FrameIntentContext.requireRegistry()
        do { try await FrameCommandService(registry: registry).pause() }
        catch { throw FrameIntentError(error) }
        return .result()
    }
}

struct ResumeSlideshowIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Slideshow"
    static let description = IntentDescription("Resumes the photo frame's slideshow.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let registry = try FrameIntentContext.requireRegistry()
        do { try await FrameCommandService(registry: registry).resume() }
        catch { throw FrameIntentError(error) }
        return .result()
    }
}

struct NextPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Photo"
    static let description = IntentDescription("Shows the next photo — without resuming when paused.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let registry = try FrameIntentContext.requireRegistry()
        do { try await FrameCommandService(registry: registry).nextPhoto() }
        catch { throw FrameIntentError(error) }
        return .result()
    }
}

struct PreviousPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Photo"
    static let description = IntentDescription("Shows the previous photo — without resuming when paused.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let registry = try FrameIntentContext.requireRegistry()
        do { try await FrameCommandService(registry: registry).previousPhoto() }
        catch { throw FrameIntentError(error) }
        return .result()
    }
}

struct SelectSourceIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Frame Source"
    static let description = IntentDescription("Switches the slideshow to one of the frame's saved sources.")
    static let openAppWhenRun = true

    @Parameter(title: "Source")
    var source: SourceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set frame source to \(\.$source)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let registry = try FrameIntentContext.requireRegistry()
        do { try await FrameCommandService(registry: registry).selectSource(id: source.id, label: source.label) }
        catch { throw FrameIntentError(error) }
        return .result()
    }
}

struct GetFrameStateIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Frame State"
    static let description = IntentDescription("Reads the frame's playback state, brightness, active source, and current photo date and place.")
    // The read intent never yanks the frame open — it answers when the app is
    // live and fails readably otherwise (research R1, FR-800-04).
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<FrameStateEntity> {
        let registry = try FrameIntentContext.requireRegistry()
        do {
            let snapshot = try await FrameCommandService(registry: registry).frameState()
            return .result(value: FrameStateEntity(snapshot))
        } catch {
            throw FrameIntentError(error)
        }
    }
}

struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Frame Brightness"
    static let description = IntentDescription("Sets the frame's screen brightness (0–100 %). Applies while the app is in the foreground.")
    static let openAppWhenRun = true

    @Parameter(title: "Brightness", inclusiveRange: (0, 100))
    var brightness: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set frame brightness to \(\.$brightness) percent")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let registry = try FrameIntentContext.requireRegistry()
        do { try await FrameCommandService(registry: registry).setBrightness(percent: brightness) }
        catch { throw FrameIntentError(error) }
        return .result()
    }
}
