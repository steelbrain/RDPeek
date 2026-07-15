import XCTest

final class RemoteDesktopRendererTests: XCTestCase {
    func testHealthyRendererEnqueuesWithoutFlushing() {
        XCTAssertEqual(
            rdpSampleBufferDisplayDisposition(
                displayFormatWillChange: false,
                rendererFailed: false,
                requiresFlushToResume: false
            ),
            .enqueue
        )
    }

    func testRendererFlushesForEveryRecoveryCondition() {
        XCTAssertEqual(
            rdpSampleBufferDisplayDisposition(
                displayFormatWillChange: true,
                rendererFailed: false,
                requiresFlushToResume: false
            ),
            .flushAndEnqueue
        )
        XCTAssertEqual(
            rdpSampleBufferDisplayDisposition(
                displayFormatWillChange: false,
                rendererFailed: true,
                requiresFlushToResume: false
            ),
            .flushAndEnqueue
        )
        XCTAssertEqual(
            rdpSampleBufferDisplayDisposition(
                displayFormatWillChange: false,
                rendererFailed: false,
                requiresFlushToResume: true
            ),
            .flushAndEnqueue
        )
    }
}
