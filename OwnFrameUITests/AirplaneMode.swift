//
//  AirplaneMode.swift
//  OwnFrameUITests
//
//  Real-device airplane mode, driven through Control Center, for the resilience and offline
//  device tests (hitl.md "Automation assessment"). There is no API for it — `devicectl` can't
//  condition a device's network — so the tests flip the same switch a person would.
//
//  Needs the device on a CABLE: airplane mode cuts Wi-Fi, and with it a wireless runner.
//  Device-only; the simulator has no Control Center switch that affects the host network.
//

import XCTest

@MainActor
enum AirplaneMode {
    private static var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// Sets airplane mode, then brings `app` back to the foreground. Fails the test if the
    /// switch can't be found or doesn't take.
    static func set(_ on: Bool, returningTo app: XCUIApplication,
                    file: StaticString = #filePath, line: UInt = #line) {
        // The edge-swipe coordinates below only hit Control Center in portrait: in landscape
        // SpringBoard's normalized frame maps them to another edge and the app's menu bar opens
        // instead (jk, iPadOS 26, soak run 2026-09-26). DeviceAcceptanceUITests forced portrait
        // in setUp, which is why the helper only ever passed there.
        XCUIDevice.shared.orientation = .portrait
        openControlCenter()
        let toggle = button()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "Control Center should show the airplane mode switch", file: file, line: line)
        if isOn(toggle) != on { toggle.tap() }
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in isOn(toggle) == on }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed,
                       "airplane mode should be \(on ? "on" : "off")", file: file, line: line)
        closeControlCenter()
        app.activate()
    }

    /// Offline for the tests means the DEVICE can't reach the server, not that a switch is on:
    /// iOS keeps Wi-Fi up in airplane mode if the person once turned it back on there. So this
    /// probes from the runner process (same device, same network) and fails if reality
    /// disagrees — otherwise an "offline" test could pass online.
    static func assertServer(_ url: URL, reachable: Bool,
                             file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(60) // Wi-Fi rejoin can be slow
        var last = !reachable
        repeat {
            last = probe(url)
            if last == reachable { return }
            Thread.sleep(forTimeInterval: 2)
        } while Date() < deadline
        XCTFail(reachable
                    ? "the device should reach \(url.host ?? "") again with airplane mode off"
                    : "the device still reaches \(url.host ?? "") with airplane mode on — Wi-Fi kept on in airplane mode?",
                file: file, line: line)
    }

    private static func probe(_ url: URL) -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            ok = (response as? HTTPURLResponse) != nil
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 8)
        return ok
    }

    /// Control Center's airplane switch: identified by its id where iOS sets one, otherwise by
    /// its (English or German) label.
    static func button() -> XCUIElement {
        springboard.buttons.matching(NSPredicate(
            format: "identifier CONTAINS[c] 'airplane' OR label IN %@",
            ["Airplane Mode", "Flugmodus"]
        )).firstMatch
    }

    private static func isOn(_ toggle: XCUIElement) -> Bool {
        if let value = toggle.value as? String { return value == "1" || value.lowercased() == "on" || value == "Ein" }
        if let value = toggle.value as? NSNumber { return value.boolValue }
        return toggle.isSelected
    }

    /// Top-right edge swipe — Control Center's gesture on every iPad and Face ID iPhone.
    static func openControlCenter() {
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.002))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private static func closeControlCenter() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        top.press(forDuration: 0.05, thenDragTo: bottom)
    }
}
