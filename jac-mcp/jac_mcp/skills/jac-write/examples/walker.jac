"""OSP walker patterns: accumulator, counter, and search-with-disengage.

Run with: jac walker.jac
"""

node Task {
    has title: str,
        done: bool = False;
}

# ---- Accumulator pattern: walk the graph, collect typed nodes, report once ----
walker ListTasks {
    has results: list[Task] = [];

    can start with Root entry {
        visit [-->];
    }

    can collect with Task entry {
        self.results.append(here);
    }

    can finish with Root exit {
        report self.results;
    }
}

# ---- Counter pattern: aggregate without collecting the full list ----
walker CountTasks {
    has total: int = 0,
        completed: int = 0;

    can start with Root entry {
        visit [-->];
    }

    can count with Task entry {
        self.total += 1;
        if here.done {
            self.completed += 1;
        }
    }

    can finish with Root exit {
        report {"total": self.total, "completed": self.completed};
    }
}

# ---- Search-with-disengage: stop early once found ----
walker ToggleTask {
    has task_id: str;

    can search with Root entry {
        visit [-->];
    }

    can toggle with Task entry {
        if jid(here) == self.task_id {
            here.done = not here.done;
            report here;
            disengage;
        }
    }
}

with entry {
    root ++> Task(title="Buy groceries");
    root ++> Task(title="Go running", done=True);
    root ++> Task(title="Read book");
}

glob list_result = root spawn ListTasks();

with entry {
    for t in list_result.reports[0] {
        print(f"- {t.title} [{('done' if t.done else 'pending')}]");
    }
}

glob count_result = root spawn CountTasks();

with entry {
    print(count_result.reports[0]);
}
