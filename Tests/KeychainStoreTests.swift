import XCTest
@testable import macHDL

/// Round-trips against the real Keychain using a dedicated test-only
/// service/account -- never touches TVEpisodeMetadataFetcher's real
/// service/account constants, so this can't clobber a developer's actual
/// stored TMDB key.
final class KeychainStoreTests: XCTestCase {
    private let service = "mac-hdl-gui-tests.keychain-store"
    private let account = "test-account"

    override func tearDown() {
        KeychainStore.delete(service: service, account: account)
        super.tearDown()
    }

    func testGetReturnsNilWhenNothingStored() {
        XCTAssertNil(KeychainStore.get(service: service, account: account))
    }

    func testSetThenGetRoundTrips() throws {
        try KeychainStore.set("s3cr3t", service: service, account: account)
        XCTAssertEqual(KeychainStore.get(service: service, account: account), "s3cr3t")
    }

    func testSetTwiceOverwritesRatherThanFailing() throws {
        try KeychainStore.set("first", service: service, account: account)
        try KeychainStore.set("second", service: service, account: account)
        XCTAssertEqual(KeychainStore.get(service: service, account: account), "second")
    }

    func testDeleteRemovesStoredValue() throws {
        try KeychainStore.set("s3cr3t", service: service, account: account)
        KeychainStore.delete(service: service, account: account)
        XCTAssertNil(KeychainStore.get(service: service, account: account))
    }

    func testDeleteWhenNothingStoredIsANoOp() {
        KeychainStore.delete(service: service, account: account)
        XCTAssertNil(KeychainStore.get(service: service, account: account))
    }
}
