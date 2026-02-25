import from os { path as os_path }

glob VERSION: str = "1.0.0";

enum Priority {
    LOW = "low",
    MEDIUM = "medium",
    HIGH = "high"
}

obj Task {
    has title: str;
    has done: bool = False;
    has priority: Priority = Priority.LOW;
}

node TaskNode {
    has task: Task;
}

def format_task(task: Task) -> str {
    return f"[{task.priority.value}] {task.title}";
}

walker TaskLister {
    has results: list = [];

    can list_tasks with `root entry {
        visit [-->];
    }

    can collect with TaskNode entry {
        report here.task;
    }
}

with entry {
    t = Task(title="Hello World");
    print(format_task(t));
}
