import Testing
@testable import SlideshowKit

@Suite
struct TVChromeModelTests {
    @Test
    func startsHidden() {
        let model = TVChromeModel()
        #expect(model.state == .hidden)
        #expect(model.isVisible == false)
    }

    @Test
    func remoteActivityRevealsAndArmsDeadline() {
        var model = TVChromeModel()
        model.remoteActivity(now: .seconds(10))
        #expect(model.isVisible)
        #expect(model.state == .visible(until: .seconds(10) + TVChromeModel.autoHide))
    }

    @Test
    func tickBeforeDeadlineKeepsVisible() {
        var model = TVChromeModel()
        model.remoteActivity(now: .seconds(10))
        model.tick(now: .seconds(10) + TVChromeModel.autoHide - .milliseconds(1))
        #expect(model.isVisible)
    }

    @Test
    func tickAtDeadlineHides() {
        var model = TVChromeModel()
        model.remoteActivity(now: .seconds(10))
        model.tick(now: .seconds(10) + TVChromeModel.autoHide)
        #expect(model.state == .hidden)
    }

    @Test
    func tickAfterDeadlineHides() {
        var model = TVChromeModel()
        model.remoteActivity(now: .seconds(10))
        model.tick(now: .seconds(100))
        #expect(model.state == .hidden)
    }

    @Test
    func tickWhileHiddenStaysHidden() {
        var model = TVChromeModel()
        model.tick(now: .seconds(5))
        #expect(model.state == .hidden)
    }

    @Test
    func repeatedActivityReArmsDeadline() {
        var model = TVChromeModel()
        model.remoteActivity(now: .seconds(10))
        // A second activity before the first deadline pushes the deadline out.
        model.remoteActivity(now: .seconds(13))
        #expect(model.state == .visible(until: .seconds(13) + TVChromeModel.autoHide))
        // The old deadline no longer hides it.
        model.tick(now: .seconds(10) + TVChromeModel.autoHide)
        #expect(model.isVisible)
        // The new deadline does.
        model.tick(now: .seconds(13) + TVChromeModel.autoHide)
        #expect(model.state == .hidden)
    }

    @Test
    func menuWhenVisibleConsumesAndHides() {
        var model = TVChromeModel()
        model.remoteActivity(now: .seconds(10))
        let consumed = model.menuPressed()
        #expect(consumed == true)
        #expect(model.state == .hidden)
    }

    @Test
    func menuWhenHiddenIsNotConsumed() {
        var model = TVChromeModel()
        let consumed = model.menuPressed()
        #expect(consumed == false)
        #expect(model.state == .hidden)
    }
}
