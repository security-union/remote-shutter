import XCTest
@testable import RemoteShutter

/// Table tests for the two pure pieces of the pairing gate: parsing a version
/// string, and turning a pair of versions into a verdict.
final class SemanticVersionTests: XCTestCase {

    func testParsesFullTriple() {
        let version = SemanticVersion(parsing: "9.0.2")
        XCTAssertEqual(version, SemanticVersion(major: 9, minor: 0, patch: 2))
    }

    func testMissingComponentsDefaultToZero() {
        XCTAssertEqual(SemanticVersion(parsing: "9.1"), SemanticVersion(major: 9, minor: 1, patch: 0))
        XCTAssertEqual(SemanticVersion(parsing: "9"), SemanticVersion(major: 9, minor: 0, patch: 0))
    }

    func testDiscardsPrereleaseAndBuildMetadata() {
        XCTAssertEqual(SemanticVersion(parsing: "9.1.0-beta.2"), SemanticVersion(major: 9, minor: 1))
        XCTAssertEqual(SemanticVersion(parsing: "9.1.0+108"), SemanticVersion(major: 9, minor: 1))
        XCTAssertEqual(SemanticVersion(parsing: "10.0.0-rc.1+ci.7"), SemanticVersion(major: 10))
    }

    func testIgnoresSurroundingWhitespaceAndExtraComponents() {
        XCTAssertEqual(SemanticVersion(parsing: "  9.0.2  "), SemanticVersion(major: 9, minor: 0, patch: 2))
        XCTAssertEqual(SemanticVersion(parsing: "9.0.2.4"), SemanticVersion(major: 9, minor: 0, patch: 2))
    }

    func testRejectsUnparseableStrings() {
        for raw in ["", "   ", "abc", "9.x", "9.0.x", "v9.0.2", "-1.0.0", ".", "9..2"] {
            XCTAssertNil(SemanticVersion(parsing: raw), "\"\(raw)\" must not parse")
        }
    }

    func testOrderingIsLexicographicOverMajorMinorPatch() {
        let ascending = [
            SemanticVersion(major: 8, minor: 9, patch: 9),
            SemanticVersion(major: 9),
            SemanticVersion(major: 9, minor: 0, patch: 2),
            SemanticVersion(major: 9, minor: 1),
            SemanticVersion(major: 10),
        ]
        XCTAssertEqual(ascending.sorted(), ascending)
        XCTAssertLessThan(SemanticVersion(major: 9, minor: 0, patch: 2), SemanticVersion(major: 9, minor: 1))
    }

    func testPrereleaseComparesEqualToRelease() {
        XCTAssertEqual(SemanticVersion(parsing: "9.1.0-beta.2"), SemanticVersion(parsing: "9.1.0"))
    }

    func testDescriptionIsAlwaysAFullTriple() {
        XCTAssertEqual(SemanticVersion(parsing: "9.1")?.description, "9.1.0")
    }
}

final class PeerAppCompatibilityTests: XCTestCase {

    private let local = SemanticVersion(major: 9, minor: 0, patch: 2)

    private func verdict(_ remote: String?) -> PeerAppCompatibility.Verdict {
        PeerAppCompatibility.decide(local: local, remoteShortVersion: remote)
    }

    func testSameMajorIsCompatibleRegardlessOfMinorOrPatch() {
        for remote in ["9.0.2", "9.0.0", "9.9.9", "9", "9.0.2-beta.1"] {
            XCTAssertEqual(verdict(remote), .compatible, "\(remote) shares this major")
        }
    }

    func testLowerMajorMeansThePeerUpdates() {
        XCTAssertEqual(verdict("8.9.9"), .peerNeedsUpdate)
        XCTAssertEqual(verdict("1.0.0"), .peerNeedsUpdate)
        XCTAssertEqual(verdict("0"), .peerNeedsUpdate)
    }

    func testHigherMajorMeansThisDeviceUpdates() {
        XCTAssertEqual(verdict("10.0.0"), .selfNeedsUpdate)
        XCTAssertEqual(verdict("12.4.1"), .selfNeedsUpdate)
    }

    /// A peer that announces nothing usable is not given the benefit of the
    /// doubt: no version, no session.
    func testMissingOrUnparseableVersionIsUnknown() {
        XCTAssertEqual(verdict(nil), .unknownPeerVersion)
        XCTAssertEqual(verdict(""), .unknownPeerVersion)
        XCTAssertEqual(verdict("unknown"), .unknownPeerVersion)
        XCTAssertEqual(verdict("v9"), .unknownPeerVersion)
    }

    /// The gate reads this build's own marketing version, so it has to be
    /// parseable in the shipped Info.plist or every peer looks incompatible.
    func testLocalVersionIsParseableInTheHostBundle() throws {
        let local = try XCTUnwrap(PeerAppCompatibility.localVersion,
                                 "CFBundleShortVersionString must parse as semver")
        XCTAssertGreaterThan(local.major, 0)
    }

    func testVerdictIsSymmetricBetweenTwoPeers() {
        let older = SemanticVersion(major: 9, minor: 3)
        let newer = SemanticVersion(major: 10)
        XCTAssertEqual(PeerAppCompatibility.decide(local: older, remoteShortVersion: newer.description),
                       .selfNeedsUpdate)
        XCTAssertEqual(PeerAppCompatibility.decide(local: newer, remoteShortVersion: older.description),
                       .peerNeedsUpdate)
    }
}
