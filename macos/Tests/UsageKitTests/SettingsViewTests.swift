import XCTest
@testable import UsageKit

final class SettingsViewTests: XCTestCase {
    func testSupportsLaunchAtLoginManagementForSystemApplications() {
        XCTAssertTrue(
            supportsLaunchAtLoginManagement(
                appURL: URL(fileURLWithPath: "/Applications/UsageKit.app"),
                installDirectories: [
                    URL(fileURLWithPath: "/Applications", isDirectory: true),
                    URL(fileURLWithPath: "/Users/test/Applications", isDirectory: true)
                ]
            )
        )
    }

    func testSupportsLaunchAtLoginManagementForUserApplications() {
        XCTAssertTrue(
            supportsLaunchAtLoginManagement(
                appURL: URL(fileURLWithPath: "/Users/test/Applications/UsageKit.app"),
                installDirectories: [
                    URL(fileURLWithPath: "/Applications", isDirectory: true),
                    URL(fileURLWithPath: "/Users/test/Applications", isDirectory: true)
                ]
            )
        )
    }

    func testDoesNotSupportLaunchAtLoginOutsideApplicationsFolders() {
        XCTAssertFalse(
            supportsLaunchAtLoginManagement(
                appURL: URL(fileURLWithPath: "/Users/test/Downloads/UsageKit.app"),
                installDirectories: [
                    URL(fileURLWithPath: "/Applications", isDirectory: true),
                    URL(fileURLWithPath: "/Users/test/Applications", isDirectory: true)
                ]
            )
        )
    }
}
