import Correcto
import CorrectoCheck
import XCTest

@testable import SessionModel

/// The acceptance test for the photo slice.
///
/// Two jobs. `PhotoCamera` must keep every rule over every reachable state.
/// And the checker, given only those rules, must rediscover the two defects a
/// person already found and reproduced on the simulator in
/// `CorrectoReproductionTests`, which is what `PhotoCameraAsShipped` is for. A
/// checker that cannot find bugs we already have has no business being trusted
/// on the ones nobody has.
final class PhotoSliceTests: XCTestCase {

    // MARK: - Environment

    /// What the world is allowed to do to the camera, and how often. Budgets
    /// keep the search finite.
    struct PhotoEnv: Hashable, Codable, Sendable {
        var timers = Timers<String>()
        var capture = Oracle<String>()
        var shutterPresses: Int
        var disconnects: Int
    }

    static let cam: MachineID = "camera"

    /// Note what is not here: nothing cancels the watchdog. The app arms a
    /// `DispatchQueue.asyncAfter` that always fires and relies on the
    /// generation to make stale ones harmless, so the model does the same.
    static func environment<M: Model>() -> Environment<M, PhotoEnv>
    where M.State == PhotoState, M.Event == PhotoEvent, M.Effect == PhotoEffect {
        Environment(
            absorb: { env, from, effects in
                for effect in effects {
                    switch effect {
                    case let .armTimeout(generation):
                        env.timers.arm("watchdog", generation: generation, owner: from)
                    case .takePicture:
                        env.capture.request("capture", from: from)
                    default:
                        break
                    }
                }
            },
            choices: { env, machines in
                var out: [Choice<M, PhotoEnv>] = []

                if env.shutterPresses > 0, machines[cam]?.phase == .camera {
                    var next = env
                    next.shutterPresses -= 1
                    out.append(Choice("press shutter", deliver: .pressShutter(sendMediaToPeer: true),
                                      to: cam, env: next))
                }
                if env.disconnects > 0, machines[cam]?.linked == true {
                    var next = env
                    next.disconnects -= 1
                    out.append(Choice("peer says goodbye", deliver: .endSession, to: cam, env: next))
                }

                // The watchdog may fire at any moment after arming.
                out += env.timers.choices(in: env, at: \.timers) { .stateTimeout(generation: $0.generation) }

                // The capture answers, one way or the other. Modelling it as an
                // oracle is what makes "the answer arrives after the watchdog"
                // an order the checker has to try.
                out += env.capture.choices(
                    in: env, at: \.capture,
                    outcomes: { _ in [true, false] },
                    event: { _, ok in ok ? .pictureCaptured : .captureFailed })

                return out
            })
    }

    static func world<M: Model>(presses: Int = 1, disconnects: Int = 1) -> World<M, PhotoEnv>
    where M.State == PhotoState {
        World(machines: [cam: PhotoState()],
              env: PhotoEnv(shutterPresses: presses, disconnects: disconnects))
    }

    // MARK: - Rules

    /// Rule 2 of the design doc. The app enforces this with a cleanup call in
    /// three places, all inside one state's handler.
    static func alertRule<M: Model>() -> WorldInvariant<M, PhotoEnv> where M.State == PhotoState {
        WorldInvariant("an alert is up only while taking a picture") { world in
            guard let state = world.machines[cam] else { return true }
            if case .takingPic = state.phase { return true }
            return !state.alertUp
        }
    }

    /// Rule 6, the terminal one. The only rule on the list that catches a lost
    /// photo, because losing data to a message arriving in a state that ignores
    /// it is not something a "must never be true" sentence describes.
    static func noLostCaptureRule<M: Model>() -> WorldInvariant<M, PhotoEnv> where M.State == PhotoState {
        WorldInvariant("when nothing more can happen, no capture is unaccounted for",
                       when: .quiescent) { world in
            world.machines[cam]?.captureOutstanding == false
        }
    }

    /// Rule 1. The generation guard the app already has. Expected to hold.
    static func staleTimeoutRule<M: Model>() -> TransitionInvariant<M>
    where M.State == PhotoState, M.Event == PhotoEvent {
        TransitionInvariant("a timeout for a stale generation changes nothing") { transition in
            guard case let .stateTimeout(fired) = transition.event else { return true }
            guard case let .takingPic(_, current) = transition.before.phase else { return true }
            if fired == current { return true }
            return transition.after == transition.before
        }
    }

    // MARK: - Acceptance: the checker must rediscover both defects

    func testCheckerFindsTheOrphanedAlert() {
        let checker = Explorer<PhotoCameraAsShipped, PhotoEnv>(
            environment: Self.environment(), invariants: [Self.alertRule()])
        let report = checker.explore(from: Self.world())

        guard let violation = report.violation else {
            return XCTFail("the checker did not find the orphaned alert:\n\(report)")
        }
        XCTAssertEqual(violation.invariant, "an alert is up only while taking a picture")
        print("\n=== orphaned alert ===\n\(report)\n")
    }

    func testCheckerFindsTheLostPhoto() {
        let checker = Explorer<PhotoCameraAsShipped, PhotoEnv>(
            environment: Self.environment(), invariants: [Self.noLostCaptureRule()])
        let report = checker.explore(from: Self.world(disconnects: 0))

        guard let violation = report.violation else {
            return XCTFail("the checker did not find the lost photo:\n\(report)")
        }
        XCTAssertEqual(violation.invariant,
                       "when nothing more can happen, no capture is unaccounted for")
        print("\n=== lost photo ===\n\(report)\n")
    }

    /// The guard the app already has should survive the same search.
    func testTheGenerationGuardHolds() {
        let checker = Explorer<PhotoCamera, PhotoEnv>(
            environment: Self.environment(),
            invariants: [],
            transitionInvariants: [Self.staleTimeoutRule()])
        let report = checker.explore(from: Self.world(presses: 2))
        XCTAssertNil(report.violation, "the generation guard should hold:\n\(report)")
    }

    // MARK: - The model itself

    func testTheModelKeepsEveryRule() {
        let checker = Explorer<PhotoCamera, PhotoEnv>(
            environment: Self.environment(),
            invariants: [Self.alertRule(), Self.noLostCaptureRule()],
            transitionInvariants: [Self.staleTimeoutRule()])
        let report = checker.explore(from: Self.world(presses: 2, disconnects: 1))

        XCTAssertNil(report.violation, "the model must keep every rule:\n\(report)")
        XCTAssertFalse(report.hitDepthLimit, "the search must finish, not stop at a limit")
        XCTAssertFalse(report.hitWorldLimit, "the search must finish, not stop at a limit")
        print("\n=== the model ===\n\(report)\n")
    }
}
