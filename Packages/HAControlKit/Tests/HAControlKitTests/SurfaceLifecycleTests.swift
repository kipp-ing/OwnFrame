import Foundation
import Testing
@testable import HAControlKit

/// The extracted teardown-decision seam (FR-700-23): a slideshow surface's `onDisappear`
/// fires both for genuine exits AND for in-app modal covers (observed on iOS 17 hardware;
/// structural on tvOS, where `fullScreenCover` removes the covered view). The decision is
/// made by *why* — the presenting layer's modal state — never by the lifecycle callback
/// itself. Leaving the foreground always tears down (FR-400-03).
@MainActor
@Suite
struct SurfaceLifecycleTests {

    // @covers FR-700-23, SC-700-15
    @Test
    func modalCoveredDisappearanceKeepsTheSessionAndTheKeepAwakeHold() {
        #expect(SlideshowSurfaceLifecycle.decision(for: .viewDisappeared, isModalPresented: true) == .keepAlive)
    }

    // @covers FR-700-23
    @Test
    func genuineExitDisappearanceTearsDown() {
        #expect(SlideshowSurfaceLifecycle.decision(for: .viewDisappeared, isModalPresented: false) == .tearDown)
    }

    // @covers FR-700-23
    @Test
    func leavingTheForegroundAlwaysTearsDownEvenUnderAModal() {
        #expect(SlideshowSurfaceLifecycle.decision(for: .leftForeground, isModalPresented: true) == .tearDown)
        #expect(SlideshowSurfaceLifecycle.decision(for: .leftForeground, isModalPresented: false) == .tearDown)
    }
}

/// The identity-scoped coordinator owner. Skipping teardown on a modal cover (above) is
/// only safe if a surface that is *destroyed* while covered (reset or a source switch
/// triggered from inside a sheet) can never leak its coordinator: two live transports
/// would share one MQTT client id and take each other over in a loop. The lease's deinit
/// is the backstop that guarantees the stop.
@MainActor
@Suite
struct HACoordinatorLeaseTests {

    // @covers FR-700-23
    @Test
    func stopStopsAndReleasesTheCoordinator() async throws {
        let transport = FakeMQTTTransport()
        let lease = HACoordinatorLease()
        let coordinator = makeCoordinator(transport: transport)
        await coordinator.start()
        lease.adopt(coordinator)

        await lease.stop()

        #expect(lease.coordinator == nil)
        #expect(transport.disconnectCount == 1)
        #expect(transport.published.last?.topic == HATopics.availability(deviceID: "dev1"))
        #expect(transport.published.last?.payload == Data("offline".utf8))
    }

    // @covers FR-700-23, SC-700-15
    @Test
    func releasingTheLeaseStopsTheAdoptedCoordinator() async throws {
        let transport = FakeMQTTTransport()
        var lease: HACoordinatorLease? = HACoordinatorLease()
        let coordinator = makeCoordinator(transport: transport)
        await coordinator.start()
        lease?.adopt(coordinator)

        lease = nil
        // The deinit schedules the stop on the main actor; pump until it lands.
        for _ in 0..<200 where transport.disconnectCount == 0 { await Task.yield() }

        #expect(transport.disconnectCount == 1,
                "destroying the owning identity must stop the coordinator — a leaked live transport would fight its successor for the MQTT client id")
        #expect(transport.published.contains {
            $0.topic == HATopics.availability(deviceID: "dev1") && $0.payload == Data("offline".utf8) && $0.retain
        })
    }

    // @covers FR-700-23
    @Test
    func adoptingAReplacementStopsThePreviousCoordinator() async throws {
        let oldTransport = FakeMQTTTransport()
        let newTransport = FakeMQTTTransport()
        let lease = HACoordinatorLease()
        let old = makeCoordinator(transport: oldTransport)
        await old.start()
        lease.adopt(old)

        let replacement = makeCoordinator(transport: newTransport)
        lease.adopt(replacement)
        for _ in 0..<200 where oldTransport.disconnectCount == 0 { await Task.yield() }

        #expect(oldTransport.disconnectCount == 1)
        #expect(lease.coordinator === replacement)
        #expect(newTransport.disconnectCount == 0)
    }

    // @covers FR-700-23
    @Test
    func emptyLeaseStopAndDeinitAreNoOps() async throws {
        var lease: HACoordinatorLease? = HACoordinatorLease()
        await lease?.stop()
        #expect(lease?.coordinator == nil)
        lease = nil
        // Nothing to assert beyond "no crash": an unused lease must be inert, because
        // SwiftUI instantiates spare @State default values it then discards.
    }

    private func makeCoordinator(transport: FakeMQTTTransport) -> HAControlCoordinator {
        HAControlCoordinator(
            transport: transport,
            control: FakeRemoteControl(),
            configStore: FakeBrokerConfigStore(config: BrokerConfig(
                host: "broker.local", port: 8883,
                username: "secret-user", password: "secret-pass", deviceID: "dev1")),
            deviceName: "Slideshow",
            enabledEntities: [.playback, .frameStatus]
        )
    }
}
