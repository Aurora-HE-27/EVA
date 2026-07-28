import XCTest
@testable import VirtualCompanion

final class SentenceSegmenterTests: XCTestCase {
    func testSegmentsAcrossFragments() {
        var segmenter = SentenceSegmenter()

        XCTAssertEqual(segmenter.append("你好，"), [])
        XCTAssertEqual(segmenter.append("今天怎么样？我很"), ["你好，今天怎么样？"])
        XCTAssertEqual(segmenter.append("开心！"), ["我很开心！"])
        XCTAssertNil(segmenter.flush())
    }

    func testFlushesRemainder() {
        var segmenter = SentenceSegmenter()
        XCTAssertEqual(segmenter.append("还没有标点"), [])
        XCTAssertEqual(segmenter.flush(), "还没有标点")
        XCTAssertNil(segmenter.flush())
    }
}
