import XCTest

final class WatchTransferTests: XCTestCase {

    func testBoolFromBridgedBool() {
        XCTAssertTrue(watchTransferBool(true, default: false))
        XCTAssertFalse(watchTransferBool(false, default: true))
    }

    func testBoolFromNSNumber() {
        XCTAssertTrue(watchTransferBool(NSNumber(value: 1), default: false))
        XCTAssertFalse(watchTransferBool(NSNumber(value: 0), default: true))
    }

    func testBoolFallsBackToDefaultWhenAbsent() {
        XCTAssertTrue(watchTransferBool(nil, default: true))
        XCTAssertFalse(watchTransferBool(nil, default: false))
    }
}
