import SwiftUI
import UIKit

// Throwaway brightness probe. Args: --mode light|dark|watch  [--set v --at s] [--reassert s]
@main struct ProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct ProbeView: View {
    let args = ProcessInfo.processInfo.arguments
    func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    @State private var text = ""
    var body: some View {
        let mode = arg("--mode") ?? "watch"
        ZStack {
            (mode == "light" ? Color.white : Color.black).ignoresSafeArea()
            Text(text).font(.system(size: 40, design: .monospaced)).foregroundStyle(mode == "light" ? .black : .gray)
        }
        .statusBarHidden()
        .task { await run(mode) }
    }
    @MainActor func run(_ mode: String) async {
        setvbuf(stdout, nil, _IONBF, 0); UIApplication.shared.isIdleTimerDisabled = true
        let screen = UIScreen.main
        if mode == "light" { screen.brightness = 1.0 }
        if mode == "dark" { screen.brightness = 0.0 }
        let setV = arg("--set").flatMap(Double.init), setAt = arg("--at").flatMap(Double.init) ?? 0
        let reassert = arg("--reassert").flatMap(Double.init)
        let start = Date(); var didSet = false; var lastAssert = Date()
        print("PROBE start mode=\(mode) b=\(String(format: "%.3f", screen.brightness))")
        while true {
            let t = Date().timeIntervalSince(start)
            if let v = setV, !didSet, t >= setAt {
                screen.brightness = v; didSet = true; lastAssert = Date()
                print("PROBE t=\(String(format: "%.1f", t)) WRITE \(v)")
            }
            if let v = setV, didSet, let r = reassert, Date().timeIntervalSince(lastAssert) >= r {
                screen.brightness = v; lastAssert = Date()
            }
            let b = screen.brightness
            text = String(format: "%@\n%.3f", mode, b)
            print("PROBE t=\(String(format: "%.1f", t)) b=\(String(format: "%.3f", b))")
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
