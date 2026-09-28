//
//  BrightnessTraceSeam.swift
//  OwnFrame
//
//  410 device rig, DEBUG only (SC-410-02's device half). `--brightness-fixed <0…1>` runs the
//  session on in-memory Fixed settings at that level (nothing persisted); `--brightness-trace`
//  prints every brightness write and a 0.5 s sample to stdout, read with
//  `devicectl device process launch --console`. Release builds have neither.
//

#if DEBUG
import Foundation
import PowerKit
import UIKit

enum BrightnessTraceSeam {
    /// The store for this launch: in-memory Fixed at the given level when the flag is set.
    @MainActor
    static func store(arguments: [String] = ProcessInfo.processInfo.arguments) -> (any BrightnessSettingsStore)? {
        guard let index = arguments.firstIndex(of: "--brightness-fixed"),
              arguments.indices.contains(index + 1),
              let level = Double(arguments[index + 1]) else { return nil }
        return InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: level))
    }

    /// Wraps the screen so every write and a 0.5 s sample reach stdout.
    @MainActor
    static func screen(_ inner: any ScreenControlling, arguments: [String] = ProcessInfo.processInfo.arguments) -> any ScreenControlling {
        guard arguments.contains("--brightness-trace") else { return inner }
        let traced = TracingScreen(inner: inner)
        traced.startSampling()
        FileHandle.standardOutput.write(Data("BRIGHT trace on\n".utf8))
        return traced
    }
}

@MainActor
private final class TracingScreen: ScreenControlling {
    private let inner: any ScreenControlling
    private var sampler: Task<Void, Never>?

    init(inner: any ScreenControlling) {
        self.inner = inner
    }

    var brightness: Double {
        get { inner.brightness }
        set {
            inner.brightness = newValue
            Self.emit("WRITE \(String(format: "%.3f", newValue))")
        }
    }

    var isIdleTimerDisabled: Bool {
        get { inner.isIdleTimerDisabled }
        set { inner.isIdleTimerDisabled = newValue }
    }

    func startSampling() {
        sampler = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                Self.emit("READ \(String(format: "%.3f", self.inner.brightness))")
            }
        }
    }

    /// Unbuffered: `print` is block-buffered on the console pipe and would arrive in bursts.
    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data("BRIGHT \(stamp()) \(line)\n".utf8))
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.S"
        return formatter.string(from: Date())
    }
}
#endif
