import from jaclang.pycore.runtime { ExecutionContext }

"""Jac Scale Execution Context with custom memory backend."""
class JScaleExecutionContext(ExecutionContext) {
    def init(
        self: JScaleExecutionContext,
        session: (str | None) = None,
        <>root: (str | None) = None
    ) -> None;
}
