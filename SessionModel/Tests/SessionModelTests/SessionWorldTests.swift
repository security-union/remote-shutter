import Correcto
import CorrectoCheck
import SessionModel
import SessionWorld
import XCTest

/// The session machine, checked over the worlds a person can drive by hand with
/// `session-runner`. Every number in `SessionModel/README.md` comes from here.
///
/// Each test asserts two things, and the second matters as much as the first:
/// every rule holds, and the search *finished*. A pass that stopped at a budget
/// or a limit reads like a proof and is not one.
final class SessionWorldTests: XCTestCase {

    private func explore(
        _ world: World<SessionDevice, SessionEnv>, _ name: String
    ) -> Report<SessionDevice, SessionEnv> {
        let explorer = Explorer<SessionDevice, SessionEnv>(
            environment: SessionWorld.environment,
            invariants: SessionRules.all,
            transitionInvariants: SessionRules.allTransitions)
        let report = explorer.explore(from: world)
        XCTAssertNil(report.violation, "\(name):\n\(report)")
        XCTAssertTrue(report.exhaustive, "\(name): the search must finish, not stop at a limit:\n\(report)")
        print("\n=== \(name) ===\n\(report)\n")
        return report
    }

    /// Pairing, then one photo, then somebody leaves. The whole protocol this
    /// slice covers, from two devices that have never met.
    func testPairingAndAPhoto() {
        let report = explore(
            SessionWorld.pair(env: SessionEnv(invites: 1, shutterPresses: 1,
                                              recordings: 0, goodbyes: 1)),
            "pairing and a photo")
        XCTAssertEqual(report.worldsExplored, 301, "the reachable world count is a fact worth pinning")
    }

    /// Two shutter presses, which is what makes a stale watchdog from the first
    /// capture reachable while the second is running.
    func testTwoCapturesInARow() {
        explore(
            SessionWorld.pair(env: SessionEnv(invites: 1, shutterPresses: 2,
                                              recordings: 0, goodbyes: 0)),
            "two captures")
    }

    /// Video, including the transmit state the camera holds until the receiver
    /// echoes. The terminal rule is what proves it does not get stuck there.
    func testRecordingAndTransmitting() {
        explore(
            SessionWorld.paired(env: SessionEnv(invites: 0, shutterPresses: 0,
                                                recordings: 1, goodbyes: 0)),
            "recording and transmitting")
    }

    /// A photo and a recording in the same session, plus a goodbye and a link
    /// drop. This is the biggest world that still finishes, and the one worth
    /// watching as the model grows.
    func testEverythingAtOnce() {
        explore(
            SessionWorld.paired(env: SessionEnv(invites: 0, shutterPresses: 1,
                                                recordings: 1, goodbyes: 1, drops: 1)),
            "photo, video, goodbye and a drop")
    }

    /// Three devices: a remote and two cameras, assembling themselves. Two
    /// invites, so the remote can collect both, and the agreement rules have to
    /// hold through every order the two links can come up in.
    func testAssemblingTheRig() {
        explore(
            SessionWorld.rig(env: SessionEnv(invites: 2, shutterPresses: 0,
                                             recordings: 0, goodbyes: 0)),
            "assembling a rig of two cameras")
    }

    /// One tap, two cameras. The take is outstanding until the last camera
    /// reports, which is what the terminal rule checks: if a single camera's
    /// answer could be dropped, this is where it shows.
    func testAMulticamTake() {
        explore(
            SessionWorld.multicam(env: SessionEnv(invites: 0, shutterPresses: 1,
                                                  recordings: 0, goodbyes: 0)),
            "one tap, two cameras")
    }

    /// A rig losing one camera mid-take. The remote carries on with the camera
    /// it still has, and the dropped camera's half of the take must not be left
    /// outstanding forever.
    func testACameraDropsOutOfATake() {
        explore(
            SessionWorld.multicam(env: SessionEnv(invites: 0, shutterPresses: 1,
                                                  recordings: 0, goodbyes: 0, drops: 1)),
            "a camera drops out of a take")
    }

    /// Every way the two role pickers can be set, as four separate worlds.
    ///
    /// This is the shape of the correction: the role is chosen before a session
    /// exists, so it is a configuration and not a move. Checking a
    /// configuration space means one world per configuration. Two cameras can
    /// never pair, because a camera advertises and only a browsing device
    /// invites, and that is what makes the agreement rule hold rather than an
    /// assumption somebody wrote down.
    func testEveryRoleConfiguration() {
        for first in [Role.undecided, .camera] {
            for second in [Role.undecided, .camera] {
                explore(
                    World(machines: [SessionWorld.remote: DeviceState(role: first),
                                     SessionWorld.camera: DeviceState(role: second)],
                          env: SessionEnv(invites: 1, shutterPresses: 1,
                                          recordings: 0, goodbyes: 1)),
                    "roles: \(first.rawValue) and \(second.rawValue)")
            }
        }
    }

    /// Without a budget on stops, a person can press stop forever, each press
    /// arms another watchdog, and `timeoutGeneration` climbs without bound. The
    /// search then stops at its world limit, which is the one result that must
    /// never be mistaken for a pass. This test pins that it is detectable.
    func testAnUnboundedBudgetIsReportedRatherThanPassed() {
        var env = SessionEnv(invites: 0, shutterPresses: 0, recordings: 1)
        env.stops = 50   // far more than the model can use before the limit bites
        let explorer = Explorer<SessionDevice, SessionEnv>(
            environment: SessionWorld.environment,
            invariants: SessionRules.all,
            options: .init(maxDepth: 64, maxWorlds: 20_000))
        let report = explorer.explore(from: SessionWorld.paired(env: env))
        XCTAssertNil(report.violation, "nothing should break; the point is the limit:\n\(report)")
        XCTAssertFalse(report.exhaustive, "a search that hit the world limit must say so")
    }
}
