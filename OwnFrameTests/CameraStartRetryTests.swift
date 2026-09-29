//
//  CameraStartRetryTests.swift
//  OwnFrameTests
//
//  The QR scanner's camera input can fail right after "Allow" or right after the app comes back
//  to the foreground, then succeed a moment later (Framepad, 2026-09-29: "not allowed" on the
//  first try, flawless on the second). `CameraStartRetry` carries that retry, so it is tested
//  here without a camera.
//

import Foundation
import Testing
@testable import OwnFrame

@MainActor
struct CameraStartRetryTests {
    private struct Transient: Error {}

    @Test func returnsTheFirstSuccessAfterTransientFailures() async {
        var calls = 0
        let value = await CameraStartRetry.firstSuccess(attempts: 5, delay: .zero) {
            calls += 1
            if calls < 3 { throw Transient() }
            return calls
        }
        #expect(value == 3)
        #expect(calls == 3)
    }

    @Test func givesUpAfterTheLastAttempt() async {
        var calls = 0
        let value: Int? = await CameraStartRetry.firstSuccess(attempts: 4, delay: .zero) {
            calls += 1
            throw Transient()
        }
        #expect(value == nil)
        #expect(calls == 4)
    }

    @Test func stopsRetryingOnceCancelled() async {
        var calls = 0
        var cancelled = false
        let value: Int? = await CameraStartRetry.firstSuccess(
            attempts: 5, delay: .zero, shouldStop: { cancelled }
        ) {
            calls += 1
            cancelled = true
            throw Transient()
        }
        #expect(value == nil)
        #expect(calls == 1)
    }
}
