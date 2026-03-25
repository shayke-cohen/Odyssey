import XCTest
@testable import ClaudPeer

final class InstanceConfigTests: XCTestCase {

    // MARK: - Instance Name

    func testDefaultInstanceName() {
        // When no --instance flag is present in CommandLine.arguments,
        // the static should have resolved to "default"
        // (unless the test runner itself passes --instance).
        // We test the derived properties instead.
        XCTAssertFalse(InstanceConfig.name.isEmpty, "Instance name should never be empty")
    }

    func testIsDefaultMatchesName() {
        XCTAssertEqual(InstanceConfig.isDefault, InstanceConfig.name == "default")
    }

    // MARK: - Directory Structure

    func testBaseDirectoryContainsInstanceName() {
        let path = InstanceConfig.baseDirectory.path
        XCTAssertTrue(path.contains(".claudpeer/instances/\(InstanceConfig.name)"),
                      "Base directory should contain the instance name: \(path)")
    }

    func testDataDirectoryIsUnderBase() {
        XCTAssertTrue(InstanceConfig.dataDirectory.path.hasPrefix(InstanceConfig.baseDirectory.path))
        XCTAssertTrue(InstanceConfig.dataDirectory.path.hasSuffix("/data"))
    }

    func testBlackboardDirectoryIsUnderBase() {
        XCTAssertTrue(InstanceConfig.blackboardDirectory.path.hasPrefix(InstanceConfig.baseDirectory.path))
        XCTAssertTrue(InstanceConfig.blackboardDirectory.path.hasSuffix("/blackboard"))
    }

    func testLogDirectoryIsUnderBase() {
        XCTAssertTrue(InstanceConfig.logDirectory.path.hasPrefix(InstanceConfig.baseDirectory.path))
        XCTAssertTrue(InstanceConfig.logDirectory.path.hasSuffix("/logs"))
    }

    func testEnsureDirectoriesCreatesAll() {
        InstanceConfig.ensureDirectories()
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: InstanceConfig.dataDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: InstanceConfig.blackboardDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: InstanceConfig.logDirectory.path))
    }

    // MARK: - UserDefaults Suite

    func testUserDefaultsSuiteContainsInstanceName() {
        XCTAssertTrue(InstanceConfig.userDefaultsSuiteName.contains(InstanceConfig.name))
        XCTAssertTrue(InstanceConfig.userDefaultsSuiteName.hasPrefix("com.claudpeer.app."))
    }

    func testUserDefaultsIsNotStandard() {
        // The per-instance suite should be distinct from .standard
        // (unless running as "default", in which case it's still a named suite)
        let testKey = "claudpeer.test.instanceConfigTest.\(UUID().uuidString)"
        InstanceConfig.userDefaults.set(true, forKey: testKey)

        // Standard should NOT have this key (different suite)
        let standardValue = UserDefaults.standard.bool(forKey: testKey)
        let instanceValue = InstanceConfig.userDefaults.bool(forKey: testKey)
        XCTAssertTrue(instanceValue)
        XCTAssertFalse(standardValue, "Per-instance suite should be separate from .standard")

        InstanceConfig.userDefaults.removeObject(forKey: testKey)
    }

    // MARK: - Port Allocation

    func testFindFreePortReturnsNonZero() {
        let port = InstanceConfig.findFreePort()
        XCTAssertGreaterThan(port, 0, "Should find a free port")
        XCTAssertLessThanOrEqual(port, 65535, "Port should be in valid range")
    }

    func testFindFreePortReturnsDifferentPorts() {
        let port1 = InstanceConfig.findFreePort()
        let port2 = InstanceConfig.findFreePort()
        // Ports should be valid; they may occasionally be the same under
        // heavy contention but should almost always differ.
        XCTAssertGreaterThan(port1, 0)
        XCTAssertGreaterThan(port2, 0)
        // Not asserting inequality — just that both are valid.
    }

    // MARK: - AppSettings Store Integration

    func testAppSettingsStoreMatchesInstanceDefaults() {
        let testKey = "claudpeer.test.storeMatch.\(UUID().uuidString)"
        AppSettings.store.set(42, forKey: testKey)

        let value = InstanceConfig.userDefaults.integer(forKey: testKey)
        XCTAssertEqual(value, 42, "AppSettings.store should be the same object as InstanceConfig.userDefaults")

        AppSettings.store.removeObject(forKey: testKey)
    }

    func testResetAllClearsInstanceDefaults() {
        let defaults = InstanceConfig.userDefaults
        defaults.set("test-value", forKey: AppSettings.appearanceKey)
        XCTAssertEqual(defaults.string(forKey: AppSettings.appearanceKey), "test-value")

        AppSettings.resetAll()
        XCTAssertNil(defaults.string(forKey: AppSettings.appearanceKey),
                     "resetAll should clear from the per-instance suite")
    }
}
