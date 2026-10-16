import Correcto

/// The app-facing half of the model: which rules run against reality on a real
/// device, how a divergence reads in a log, and a factory so the coordinator
/// has one line to call.
///
/// See `docs/SHADOW-MODE.md` in the Correcto repository for the design, and
/// `Docs/correcto-integration.md` for where this is going.
public enum SessionShadow {

    /// The rules checked against observed reality on every message. These run
    /// on a device against real traffic, so every one has to be true of a
    /// single state, on its own, at any instant.
    ///
    /// That condition is what keeps this list short. "When nothing more can
    /// happen, nothing is left outstanding" is the rule that catches lost work,
    /// and it cannot live here: a running app never reaches quiescence, so there
    /// is no moment at which to ask. It stays a checker rule, where the explorer
    /// knows when a world has stopped.
    ///
    /// There was a second rule here once, saying a capture is outstanding only
    /// while taking a picture or just after. It reads fine and it is false: a
    /// capture outlives its phase whenever the hardware is slower than the
    /// session. A rule that is nearly right reports on ordinary usage, and the
    /// first thing anyone does about a shadow that cries wolf is switch it off.
    public static let rules: [Invariant<DeviceState>] = [
        Invariant("an alert is up only while taking a picture") { state in
            if case .cameraTakingPic = state.phase { return true }
            return !state.alertUp
        }
    ]

    public static func make(
        seededWith state: DeviceState,
        report: @escaping @Sendable (ShadowRuntime<SessionDevice>.Divergence) -> Void
    ) -> ShadowRuntime<SessionDevice> {
        ShadowRuntime<SessionDevice>(seededWith: state, rules: rules, report: report)
    }

    /// Which fields differ, named. The first divergence this reported in anger
    /// said "predicted scanning, app reached scanning", which is true of the
    /// phase and useless: the disagreement was two fields further down, and it
    /// was a defect. A report you cannot read is noise, and noise is how a
    /// shadow gets ignored.
    public static func differences(_ predicted: DeviceState, _ observed: DeviceState) -> String {
        var parts: [String] = []
        func note(_ name: String, _ left: String, _ right: String) {
            if left != right { parts.append("\(name) \(left) vs \(right)") }
        }
        note("phase", "\(predicted.phase)", "\(observed.phase)")
        note("role", predicted.role.rawValue, observed.role.rawValue)
        note("peers", predicted.peers.map(\.name).joined(separator: "+"),
             observed.peers.map(\.name).joined(separator: "+"))
        note("alertUp", "\(predicted.alertUp)", "\(observed.alertUp)")
        note("captureOutstanding", "\(predicted.captureOutstanding)", "\(observed.captureOutstanding)")
        note("capturesAwaited", "\(predicted.capturesAwaited)", "\(observed.capturesAwaited)")
        note("recordingsAwaited", "\(predicted.recordingsAwaited)", "\(observed.recordingsAwaited)")
        note("believesRecording", "\(predicted.believesRecording)", "\(observed.believesRecording)")
        note("timeoutGeneration", "\(predicted.timeoutGeneration)", "\(observed.timeoutGeneration)")
        return parts.isEmpty ? "nothing, the states are equal" : parts.joined(separator: ", ")
    }

    /// A one-line description for a log. Divergences should be rare enough that
    /// a line each is the right volume; if they are not, the model is wrong and
    /// that is what this is for.
    public static func describe(_ divergence: ShadowRuntime<SessionDevice>.Divergence) -> String {
        switch divergence {
        case let .state(events, predicted, observed, _):
            let names = events.map { "\($0)" }.joined(separator: " then ")
            return "model disagreed on \(names): \(differences(predicted, observed))"
        case let .ruleBroken(name, observed, event):
            let cause = event.map { "\($0)" } ?? "an unmodelled message"
            return "RULE BROKEN \"\(name)\" after \(cause) in \(observed.phase)"
        case let .unmodelled(observed):
            return "an unmodelled message moved the app to \(observed.phase)"
        }
    }
}
