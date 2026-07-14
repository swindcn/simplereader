import XCTest
@testable import PureVoice

final class DesignTokensTests: XCTestCase {
    func testMinimumTouchTargetMatchesApprovedDesign() {
        XCTAssertEqual(DesignTokens.minimumTouchTarget, 60)
        XCTAssertLessThanOrEqual(DesignTokens.cardRadius, 8)
    }

    func testAppTabsHaveStableOrderAndLabels() {
        XCTAssertEqual(AppTab.allCases, [.library, .importBooks, .settings])
        XCTAssertEqual(AppTab.allCases.map(\.title), ["书架", "导入", "设置"])
        XCTAssertTrue(AppTab.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }
}
