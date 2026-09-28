import Correcto

/// The photo slice's shadow, wired for `SessionCoordinator`.
///
/// Everything here is the app-facing half of the model: how a coordinator
/// message becomes a `PhotoEvent`, which rules are checked at runtime, and a
/// factory so the coordinator has one line to call rather than five.
public enum PhotoShadow {

    /// The rules checked against observed reality on every message. These are
    /// the same sentences the checker proves exhaustively in
    /// `PhotoSliceTests`; here they run on a real device against real traffic.
    public static let rules: [Invariant<PhotoState>] = [
        Invariant("an alert is up only while taking a picture") { state in
            if case .takingPic = state.phase { return true }
            return !state.alertUp
        },
        Invariant("a capture is outstanding only while taking a picture or just after") { state in
            guard state.captureOutstanding else { return true }
            if case .takingPic = state.phase { return true }
            // Settled back to idle with a capture still in flight is legal for
            // a moment: the watchdog fired and the hardware has not answered.
            return state.phase == .camera
        }
    ]

    public static func make(
        seededWith state: PhotoState,
        report: @escaping @Sendable (ShadowRuntime<PhotoCamera>.Divergence) -> Void
    ) -> ShadowRuntime<PhotoCamera> {
        ShadowRuntime<PhotoCamera>(seededWith: state, rules: rules, report: report)
    }

    /// A one-line description for a log. Divergences should be rare enough
    /// that a line each is the right volume; if they are not, the model is
    /// wrong and that is what this is for.
    public static func describe(_ divergence: ShadowRuntime<PhotoCamera>.Divergence) -> String {
        switch divergence {
        case let .state(event, predicted, observed, _):
            return "model disagreed on \(event): predicted \(predicted.phase), app reached \(observed.phase)"
        case let .ruleBroken(name, observed, event):
            let cause = event.map { "\($0)" } ?? "an unmodelled message"
            return "RULE BROKEN \"\(name)\" after \(cause) in \(observed.phase)"
        case let .unmodelled(observed):
            return "an unmodelled message moved the app to \(observed.phase)"
        }
    }
}
