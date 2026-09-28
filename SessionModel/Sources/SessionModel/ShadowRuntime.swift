import Correcto

/// Runs a model beside the code that is actually in charge, and reports where
/// the two disagree. Performs nothing, decides nothing, and cannot change what
/// the app does, because nothing downstream reads its output.
///
/// Two independent signals come out of it. Whether the model matches the app,
/// from comparing the step's prediction against what really happened. And
/// whether the app is correct, from checking the rules against what really
/// happened, which needs no correct model at all.
///
/// See `docs/SHADOW-MODE.md` in the Correcto repository for the design.
public actor ShadowRuntime<M: Model> {

    public enum Divergence: Sendable {
        /// The model predicted a different next state than the app reached.
        case state(event: M.Event, predicted: M.State, observed: M.State, effects: [M.Effect])
        /// A rule broke on the state the app actually reached. This is a defect
        /// in the app, not in the model.
        case ruleBroken(name: String, observed: M.State, lastEvent: M.Event?)
        /// A message the model does not own yet moved the app's state.
        case unmodelled(observed: M.State)
    }

    private var state: M.State
    private let rules: [Invariant<M.State>]
    private let report: @Sendable (Divergence) -> Void

    /// Seed from a projection of the live app, not from the model's initial
    /// state: the shadow is usually attached to something already running.
    public init(seededWith initial: M.State,
                rules: [Invariant<M.State>] = [],
                report: @escaping @Sendable (Divergence) -> Void) {
        self.state = initial
        self.rules = rules
        self.report = report
    }

    public var current: M.State { state }

    /// Call once per message, after the real code has finished handling it.
    /// `event` is nil for a message the model does not own yet; the shadow
    /// still needs to see it, or its state falls behind and every later
    /// comparison is noise.
    public func observe(event: M.Event?, observed: M.State) {
        if let event {
            let step = M.step(state, event)
            if step.state != observed {
                report(.state(event: event, predicted: step.state,
                              observed: observed, effects: step.effects))
            }
        } else if observed != state {
            report(.unmodelled(observed: observed))
        }

        for rule in rules where !rule.holds(observed) {
            report(.ruleBroken(name: rule.name, observed: observed, lastEvent: event))
        }

        // Resynchronise. Unconditional: when the prediction matched this is a
        // no-op, and when it did not, reality wins. No branch to get wrong, and
        // one wrong prediction costs one report rather than every report after
        // it.
        state = observed
    }
}
