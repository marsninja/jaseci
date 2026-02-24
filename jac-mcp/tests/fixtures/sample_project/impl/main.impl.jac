"""Sample project implementations."""

impl TaskRunner.run_task(self: TaskRunner) with TaskNode entry {
    if not here.done {
        here.done = True;
        self.completed.append(here.title);
    }
    visit [-->];
}
