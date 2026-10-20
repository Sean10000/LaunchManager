import XCTest
@testable import LaunchManager

final class TriggerCompilerTests: XCTestCase {
    func test_parseEntry_missingMinute_staysNil() {
        let entry = TriggerCompiler.parseEntry(["Hour": 9])
        XCTAssertEqual(entry.hour, 9)
        XCTAssertNil(entry.minute)
        XCTAssertTrue(entry.diagnostics.isEmpty)
        XCTAssertEqual(entry.raw["Hour"] as? Int, 9)
        XCTAssertNil(entry.raw["Minute"])
    }

    func test_parseEntry_invalidHour_isDiagnostic() {
        let entry = TriggerCompiler.parseEntry(["Hour": "9", "Minute": 0])
        XCTAssertNil(entry.hour)
        XCTAssertEqual(entry.minute, 0)
        XCTAssertFalse(entry.diagnostics.isEmpty)
    }

    func test_parseEntry_outOfRangeHour_isDiagnostic() {
        let entry = TriggerCompiler.parseEntry(["Hour": 99, "Minute": 0])
        XCTAssertNil(entry.hour)
        XCTAssertFalse(entry.diagnostics.isEmpty)
    }
}
