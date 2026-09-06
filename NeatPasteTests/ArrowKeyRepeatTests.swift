import AppKit
import MacKitCore
import MacKitLifecycle
import XCTest
@testable import NeatPaste
@preconcurrency import Carbon

final class ArrowKeyRepeatTests: XCTestCase {
    @MainActor
    func test_按住会按间隔连续走步() async {
        var held = true
        let repeater = ArrowKeyRepeat(delay: 0.04, interval: 0.04, isKeyPressed: { _ in held })
        var steps: [Int] = []
        let repeating = expectation(description: "连续走步")
        repeating.assertForOverFulfill = false
        repeater.onStep = { delta in
            steps.append(delta)
            if steps.count >= 3 {
                repeating.fulfill()
            }
        }

        repeater.keyDown(keyCode: 125, isARepeat: false, delta: 1)
        XCTAssertEqual(steps, [1])
        await fulfillment(of: [repeating], timeout: 1)
        XCTAssertGreaterThanOrEqual(steps.count, 3)
        XCTAssertTrue(steps.allSatisfy { $0 == 1 })

        repeater.keyUp(keyCode: 125)
        held = false
        let frozen = steps.count
        let idle = expectation(description: "松手后停")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            idle.fulfill()
        }
        await fulfillment(of: [idle], timeout: 1)
        XCTAssertEqual(steps.count, frozen)
        repeater.stop()
    }

    @MainActor
    func test_系统连发事件不再走一步() {
        let repeater = ArrowKeyRepeat(delay: 10, interval: 10, isKeyPressed: { _ in true })
        var count = 0
        repeater.onStep = { _ in count += 1 }
        repeater.keyDown(keyCode: 126, isARepeat: false, delta: -1)
        repeater.keyDown(keyCode: 126, isARepeat: true, delta: -1)
        repeater.keyDown(keyCode: 126, isARepeat: true, delta: -1)
        XCTAssertEqual(count, 1)
        repeater.stop()
    }

    @MainActor
    func test_同一键重复按下不连跳() {
        let repeater = ArrowKeyRepeat(delay: 10, interval: 10, isKeyPressed: { _ in true })
        var count = 0
        repeater.onStep = { _ in count += 1 }
        repeater.keyDown(keyCode: 125, isARepeat: false, delta: 1)
        repeater.keyDown(keyCode: 125, isARepeat: false, delta: 1)
        repeater.keyDown(keyCode: 125, isARepeat: false, delta: 1)
        XCTAssertEqual(count, 1)
        repeater.stop()
    }
}
