# The Three Paradigms -- Playbooks

Load when the task touches any of OSP (graph/walkers), MTP (AI functions), or codespaces (client/server). Each section is a full playbook with a canonical pattern and decision guidance.

---

## § OSP -- Object-Spatial Programming

Data lives in a graph anchored to `root`. Nodes connected to `root` persist automatically across process restarts. Each authenticated user gets their own private `root`. Walkers are mobile computation that visits nodes.

### Declarations

```jac
node Task {
    has title: str,
        done: bool = False;
}

edge Scheduled {
    has time: str,
        priority: int = 1;
}
```

- `node` -- persistent when reachable from `root`; otherwise garbage-collected when the current execution ends.
- `edge` -- typed connection between nodes; can carry data.
- Same syntax as `obj`. The difference is what the runtime does with them.

### Graph construction

```jac
with entry {
    root ++> Task(title="Buy groceries");
    root ++> Task(title="Go running");

    # Typed edge with edge data
    root +>: Scheduled(time="9am", priority=3) :+> Task(title="Morning run");

    # Capture the new node
    task = (root ++> Task(title="Learn Jac"))[0];
    print(jid(task));     # unique id -- no uuid library needed
}
```

`++>` creates the connection and returns a list containing the new node. `+>: EdgeType(...) :+>` creates a typed edge.

### Queries -- filter comprehensions on any collection

```jac
# All connected nodes (returns a list)
everything = [root-->];

# Filter by type
tasks = [root-->][?:Task];

# Filter by field
pending = [root-->][?:Task, done == False];

# Traversal direction
outgoing = [root-->];
incoming = [some_node<--];
both = [some_node<-->];

# Via a typed edge
scheduled = [root->:Scheduled:->][?:Task];
urgent = [root->:Scheduled:priority >= 3:->][?:Task];

# Edge objects themselves (not targets)
edges = [edge root-->];
```

The `[?:Type, field == val]` filter works on any list -- not just graph queries. The general pattern: `[--> direction]` returns a list, `[?...]` filters it.

### Walkers -- mobile computation

```jac
walker ListTasks {
    has results: list = [];

    can start with Root entry {
        visit [-->];                  # move to all connected nodes
    }

    can collect with Task entry {
        self.results.append(here);    # `here` = current node
    }

    can finish with Root exit {
        report self.results;          # sent back to spawner
    }
}

with entry {
    result = root spawn ListTasks();
    print(result.reports[0]);         # the reported list
}
```

Keywords:

- **`visit [-->]`** -- queue connected nodes for traversal (executes after current ability body finishes).
- **`here`** -- the current node the walker is visiting.
- **`self`** -- the walker itself (its `has` state).
- **`visitor`** -- inside a node-ability, the walker that's visiting.
- **`report`** -- send a value back; collected in `.reports` on the spawn result.
- **`disengage`** -- stop traversal immediately.
- **`spawn`** -- `root spawn Walker(field=value)` starts the walker at `root`.

### Walker patterns

**Accumulator** -- collect across nodes:

```jac
walker Gather {
    has items: list = [];
    can s with Root entry { visit [-->]; }
    can g with Task entry { self.items.append(here); }
    can f with Root exit { report self.items; }
}
```

**Counter** -- aggregate without storing each node:

```jac
walker Count {
    has total: int = 0;
    can s with Root entry { visit [-->]; }
    can c with Task entry { self.total += 1; }
    can f with Root exit { report self.total; }
}
```

**Search + disengage** -- stop as soon as found:

```jac
walker Find {
    has target_id: str;
    can s with Root entry { visit [-->]; }
    can t with Task entry {
        if jid(here) == self.target_id {
            report here;
            disengage;
        }
    }
}
```

**Node-side ability** -- logic on the node instead of the walker:

```jac
node Task {
    has title: str;
    can respond with ListTasks entry {
        visitor.results.append(self);    # `visitor` = the walking Walker
    }
}
```

Put the logic wherever it naturally belongs -- on the walker when it's about traversal, on the node when it's about the data.

### Deletion

```jac
del some_node;              # remove a node
a del --> b;                # remove a specific edge
```

### Decision -- walker vs `def:pub`

| Use                   | When                                                                 |
|-----------------------|----------------------------------------------------------------------|
| `def:pub` / `def:priv`| Flat CRUD, simple endpoints, quick prototyping.                      |
| `walker`              | Multi-hop traversal, accumulator across many nodes, or deep graphs.  |
| `walker:priv`         | Per-user walker -- same as `:priv` on functions.                      |
| Node-side ability     | Logic naturally belongs to the data type, not the traversal.         |

For a flat list of Tasks directly off root, `def:pub get_tasks -> list { return [root-->][?:Task]; }` is the idiomatic choice. Walker value grows with graph depth.

### Persistence -- the key insight

You never call `save()` or `commit()` in application code. The runtime persists nodes reachable from `root` automatically when the request completes. For a multi-user app:

```jac
def:priv get_my_tasks -> list[Task] {
    return [root-->][?:Task];     # `root` is THIS user's root
}
```

`def:priv` means "each authenticated user has their own private root." Zero manual user-id filtering.

---

## § MTP -- Meaning-Typed Programming (AI via byLLM)

`by llm()` replaces a function body. The signature becomes the specification. An `enum` return type constrains output to exactly those values; an `obj` return type forces structured output. `sem` attaches semantic hints to disambiguate.

### Setup

```jac
import from byllm.lib { Model }

glob llm = Model(model_name="claude-sonnet-4-20250514");
```

`glob` declares a module-level variable. The model name follows LiteLLM conventions -- Anthropic, OpenAI, Google Gemini, Ollama (self-hosted), Azure, all supported.

### Pattern 1 -- enum constraint

```jac
enum Category { WORK, PERSONAL, SHOPPING, HEALTH, OTHER }

def categorize(title: str) -> Category by llm();
sem categorize = "Categorize a task based on its title";
```

The LLM can only return one of the defined enum values. If it returns something else, the runtime catches the malformed output -- you don't need to guard against "Shopping" vs "shopping" vs "groceries."

Convert for display: `str(Category.SHOPPING).split(".")[-1].lower()` → `"shopping"`.

### Pattern 2 -- structured output with `obj` + `sem`

```jac
enum Unit { PIECE, LB, OZ, CUP, TBSP, TSP }

obj Ingredient {
    has name: str,
        quantity: float,
        unit: Unit,
        cost: float,
        carby: bool;
}

sem Ingredient.cost = "Estimated cost in USD";
sem Ingredient.carby = "True if this ingredient is high in carbohydrates";

def shopping_list(meal: str) -> list[Ingredient] by llm();
sem shopping_list = "Generate a shopping list for the described meal";
```

Every field of `Ingredient` must be filled. `sem` makes ambiguous fields unambiguous -- without `sem Ingredient.cost = "Estimated cost in USD"`, the LLM doesn't know the currency or unit scope.

### Pattern 3 -- tool calling (agentic)

```jac
def get_weather(city: str) -> str { return f"Weather data for {city}"; }
def search_web(query: str) -> list[str] { return [f"Result for {query}"]; }

def answer(question: str) -> str by llm(
    tools=[get_weather, search_web]
);
```

The LLM decides which tools to call and in what order. Each tool's signature (with `sem` hints if useful) tells the LLM how and when to call it.

### Pattern 4 -- inline prompt

```jac
with entry {
    result = "Explain quantum computing simply" by llm;
    print(result);
}
```

Rare; use when the "function" is a one-off and the function-declaration pattern is overkill.

### When to use `sem`

Use `sem` any time a type alone is ambiguous to a reader. If `cost: float` might mean USD/EUR/per-unit/per-recipe, you need `sem`. If `count: int` means something obvious from context, you don't. `sem` is not a comment -- it's a compiler directive that injects into the prompt.

Always use `sem` on `by llm()` functions themselves (the function-level instruction), unless the function name alone carries the full intent.

### Decision -- AI output type

| Need                              | Return type                           |
|-----------------------------------|---------------------------------------|
| One of N predefined values        | `enum`                                |
| A structured record               | `obj Foo { has ...; }`                |
| A list of structured records      | `list[Foo]` where `Foo` is `obj`      |
| Free-form text                    | `str` (use sparingly -- lose structure)|
| A decision + reasoning            | `obj` with multiple fields            |

Almost never return `str` from `by llm()` unless the output truly is unconstrained text (summary, translation). Any time the output has a shape, use `enum` or `obj`.

---

## § Codespaces -- Server, Client, Native

A single `.jac` file can contain code that runs on the server, in the browser, and natively -- distinguished by **codespaces**.

### Section headers and prefixes

```jac
# Default: server code (compiles to Python)
node Todo { has title: str; }
def:pub get_todos -> list { return [root-->][?:Todo]; }

to cl:                      # everything below runs in the browser

def:pub app -> JsxElement {
    has todos: list = [];
    async can with entry { todos = await get_todos(); }
    return <div>{[<p key={jid(t)}>{t.title}</p> for t in todos]}</div>;
}

to sv:                      # switch back to server
# ... more server code ...
```

- `to sv:` -- server codespace (Python/PyPI).
- `to cl:` -- client codespace (JavaScript/npm/React).
- `to na:` -- native codespace (C ABI, LLVM-compiled).
- Code before any header defaults to server.

Single-statement prefix form: `cl def:pub app -> JsxElement { ... }` tags one declaration. The braced `cl { ... }` form still works in inner scopes but emits **W0064** at module scope -- prefer `to cl:`.

### File extensions set the default

- `prog.jac` -- server default.
- `prog.cl.jac` -- client default (no wrapper needed).
- `prog.sv.jac` -- server explicit.
- `prog.na.jac` -- native.
- `prog.impl.jac` -- implementation annex for a declaration file.
- `prog.test.jac` -- test annex.

### Client components

```jac
# In a .cl.jac file, or under `to cl:`, or with `cl def:pub`:

def:pub Counter -> JsxElement {
    has count: int = 0;                       # reactive state -- compiles to useState

    async can with entry {                     # lifecycle: on mount
        # optional initial load
    }

    def increment {                            # local method
        count = count + 1;                     # reassignment triggers re-render
    }

    return
        <div>
            <p>Count: {count}</p>
            <button onClick={lambda -> None { increment(); }}>+</button>
        </div>;
}
```

Lifecycle hooks:

- `async can with entry { ... }` -- runs once on mount (like `useEffect(() => {}, [])`).
- `async can with [dep1, dep2] entry { ... }` -- runs when listed state changes.
- `can with exit { ... }` -- cleanup on unmount.

Reactive state rules:

- **Declare with `has`**, not `useState`.
- **Reassign, never mutate.** `list = list + [x]`, `dict = {**dict, k: v}`.
- JSX expressions: `{expr}`, list render `{[<X key={...}/> for x in xs]}`, conditional `{cond and <X/>}` or ternary.
- Events: typed lambda parameters (`lambda e: ChangeEvent { ... }`).

### Server-client interop

**Calling a `def:pub` / `def:priv` server function from client:**

```jac
sv import from main { add_task, get_tasks }

cl def:pub App -> JsxElement {
    has tasks: list = [];

    async can with entry {
        tasks = await get_tasks();              # transparent HTTP call
    }

    async def add(text: str) {
        new_task = await add_task(text);        # returns typed Task object
        tasks = tasks + [new_task];
    }

    return <div>{[<p key={jid(t)}>{t.title}</p> for t in tasks]}</div>;
}
```

**Calling a walker from client:**

```jac
sv import from main { AddTask, ListTasks }

cl def:pub App -> JsxElement {
    has tasks: list = [];

    async can with entry {
        result = root spawn ListTasks();
        tasks = result.reports[0];
    }

    async def add(text: str) {
        result = root spawn AddTask(title=text);
        new_task = result.reports[0];
        tasks = tasks + [new_task];
    }
}
```

**Never** use plain `import` or `fetch()` -- `sv import` tells the compiler to generate HTTP stubs.

### Auth

```jac
cl import from "@jac/runtime" { jacSignup, jacLogin, jacLogout, jacIsLoggedIn }

cl def:pub Login -> JsxElement {
    has user: str = "", pw: str = "", err: str = "";

    async def submit {
        ok = await jacLogin(user, pw);
        if not ok { err = "Invalid credentials"; }
    }

    return
        <form onSubmit={lambda e: FormEvent {
            e.preventDefault();
            submit();
        }}>
            <input value={user} onChange={lambda e: ChangeEvent { user = e.target.value; }}/>
            <input type="password" value={pw} onChange={lambda e: ChangeEvent { pw = e.target.value; }}/>
            <button type="submit">Sign in</button>
            {err and <p>{err}</p>}
        </form>;
}
```

Combined with `def:priv` / `walker:priv` on the server, each authenticated user automatically gets their own graph root. No manual JWT, no session plumbing.

### Cross-user data -- `allroots` and `grant`

Per-user isolation via `def:priv` is the default, but most real apps need *some* cross-user discovery: connection requests, a public feed of others' posts, friend search. Jac provides two primitives:

**`allroots()`** returns a list of every user's root in the system. Use it for cross-user lookups:

```jac
def:priv find_profile_by_username(target_username: str) -> Profile | None {
    for r in allroots() {
        profs = [r-->[?:Profile, username == target_username]];
        if profs {
            return profs[0];
        }
    }
    return None;
}
```

**`grant(node, level=...)`** opens a node so other users' walkers can traverse to it. Without an explicit grant, `def:priv` isolation hides nodes from other users entirely. Common access levels:

```jac
node Profile {
    has username: str = "",
        name: str = "",
        headline: str = "";
}

def:priv my_profile -> Profile {
    existing = [root-->[?:Profile]];
    if existing { return existing[0]; }

    p = Profile();
    root ++> p;
    grant(p, level=ConnectPerm);   # other users can find this profile via allroots()
    return p;
}
```

`ConnectPerm` allows other users to discover and form connection edges to this node. Use stricter levels for nodes that should stay private even when discoverable. (See `jac-scale` reference for the full permission ladder.)

This pair is how cross-user features like LinkedIn-style connection requests, discoverable user directories, and shared/public posts get built. Any time your app needs "user A interacts with user B's data," you'll need both primitives.

### Decision -- `def:pub` vs walker as endpoint

| Task                                          | Use                                     |
|-----------------------------------------------|------------------------------------------|
| Simple CRUD against flat graph                | `def:pub` / `def:priv`                   |
| Multi-step graph traversal                    | `walker:pub` / `walker:priv`             |
| Accumulator across many nodes                 | `walker` with `has results: list = [];`  |
| Endpoint that updates many nodes atomically   | `walker` -- one traversal, many updates   |
| Public API, no auth                           | `:pub` on either                         |
| Authenticated, per-user data                  | `:priv` on either                        |

---

## § Multi-file organization (declaration / implementation split)

As files grow, split declarations from implementations:

`calculator.jac`:

```jac
obj Calculator {
    has result: float = 0.0;
    def add(x: float) -> float;
    def multiply(x: float) -> float;
    def reset -> None;
}
```

`calculator.impl.jac`:

```jac
impl Calculator.add(x: float) -> float {
    self.result += x;
    return self.result;
}

impl Calculator.multiply(x: float) -> float {
    self.result *= x;
    return self.result;
}

impl Calculator.reset -> None {
    self.result = 0.0;
}
```

Same pattern for components -- **except lifecycle hooks**:

`frontend.cl.jac`:

```jac
def:pub MyApp -> JsxElement {
    has tasks: list = [];

    async can with entry {           # LIFECYCLE HOOK -- stays inline
        tasks = await get_tasks();
    }

    async def fetchTasks;             # named -- declaration
    async def addTask(title: str);    # named -- declaration
    # ... render tree ...
}
```

`frontend.impl.jac`:

```jac
impl MyApp.fetchTasks {
    tasks = await get_tasks();
}

impl MyApp.addTask(title: str) {
    new_task = await add_task(title);
    tasks = tasks + [new_task];
}
```

**Lifecycle hooks (`can with entry` / `can with exit` / `can with [deps] entry`) cannot be moved to an `.impl.jac` file** -- `impl MyApp.with entry { ... }` is a parse error. Keep them inline in the declaration; only named `def`/`can` can be split out.

**A single parse error in an `.impl.jac` file empties every `impl` block in that file.** If "missing implementation" errors appear mysteriously, run `jac check` on the impl file first.

---

## § Full-stack multi-file shape (main.jac + frontend.cl.jac + frontend.impl.jac)

This is the canonical layout for any non-trivial full-stack Jac app. The AI Day Planner tutorial uses it; the LinkedIn-lite skill-test app uses it. Learn this shape -- it doesn't appear explicitly elsewhere in the docs and costs time to reinvent.

### Project layout

```
myapp/
├── jac.toml              # project manifest -- REQUIRED for `jac start`
├── main.jac              # server: nodes, endpoints, AI, + a thin client wrapper that mounts the component
├── frontend.cl.jac       # client: component declaration + reactive state + render tree + lifecycle hooks
├── frontend.impl.jac     # client: handler bodies (method impls)
└── styles.css            # (optional; see static assets caveat below)
```

### `jac.toml` -- the project manifest

`jac start` refuses to boot without a `jac.toml` at the project root. Bare `jac main.jac` (script mode) doesn't need one, but the moment you want HTTP serving you need the manifest. A minimal version:

```toml
[project]
name = "myapp"
entry-point = "main.jac"

[serve]
base_route_app = "app"
```

`base_route_app = "app"` tells the dev server to mount the `def:pub app` component at `/cl/app`. After `jac start main.jac --port 8000`, the page renders at `http://localhost:8000/cl/app`, and `curl http://localhost:8000/` returns a JSON catalog of every mounted endpoint and walker -- use that as your boot-verification smoke-test (there is no Swagger `/docs` route on plain `jac start`).

The `jac create myapp --use client` template scaffolds a richer `jac.toml` with npm dependency entries; for the simple multi-file shape above, the four-line manifest is enough.

### `main.jac` -- server + client mount

```jac
"""Server logic + the client entry point."""

import from byllm.lib { Model }

# ---- CLIENT MOUNT ----
# A thin `to cl:` section that re-exports the component from frontend.cl.jac.
# This is the hand-off point: the server defines the canonical `app` symbol
# that `jac start` serves, and that symbol renders the client component.

to cl:

import from frontend { MyApp }

def:pub app -> JsxElement {
    return <MyApp/>;
}

# ---- SERVER ----

to sv:

glob llm = Model(model_name="claude-sonnet-4-20250514");

node Task {
    has title: str,
        done: bool = False;
}

def:priv get_tasks -> list[Task] {
    return [root-->][?:Task];
}

def:priv add_task(title: str) -> Task {
    return (root ++> Task(title=title))[0];
}
```

Key points:

- **The `to cl:` block in `main.jac` is mandatory.** `jac start` looks for a `def:pub app` symbol in the client codespace of `main.jac`. Without the re-export wrapper, the server reports `{"error": "Client function 'app' not found"}`.
- **The wrapper function is named `app`; the imported component is anything else** (here `MyApp`). Using the same name in both files causes E2016 because the impl blocks bind to the wrong declaration.
- **Don't `include frontend;`** at module scope -- if `frontend.cl.jac` has `sv import from main { ... }` (which it does for endpoint calls), you get a circular import. The `to cl: import from frontend { MyApp }` pattern avoids the cycle because the server-side `sv import` and the client-side `import from frontend` live in different codespaces.
- **PascalCase is required.** `<MyApp/>` works; `<my_app/>` renders as a literal HTML element. See pitfalls.md rule 31.

### `frontend.cl.jac` -- component declaration

```jac
"""Client-side UI: state, lifecycle, handler signatures, render tree."""

cl import from "@jac/runtime" { jacSignup, jacLogin, jacLogout, jacIsLoggedIn }

sv import from main { get_tasks, add_task }

def:pub MyApp -> JsxElement {
    has logged_in: bool = False,
        tasks: list = [],
        draft: str = "",
        loading: bool = True;

    # Lifecycle hook -- INLINE, cannot be impl'd externally
    async can with entry {
        is_auth = jacIsLoggedIn();
        logged_in = is_auth;
        if is_auth {                         # local, not the has field (see pitfalls rule 30)
            await refresh();
        }
        loading = False;
    }

    # Handler declarations (bodies in frontend.impl.jac)
    async def refresh;
    async def do_login(user: str, pw: str);
    async def do_add_task;

    # Render tree
    if loading {
        return <div>Loading...</div>;
    }
    if not logged_in {
        return <div>... auth UI ...</div>;
    }
    return <div>
        {[<p key={jid(t)}>{t.title}</p> for t in tasks]}
        <input value={draft} onChange={lambda e: ChangeEvent { draft = e.target.value; }}/>
        <button onClick={lambda e: MouseEvent { do_add_task(); }}>Add</button>
    </div>;
}
```

Import rules:

- **`cl import from "@jac/runtime"`** -- client-side runtime helpers (auth, routing).
- **`sv import from main`** -- pulls server symbols in; the compiler generates HTTP stubs automatically.
- **Plain `import`** -- Python/Jac packages consumed on the client side.

### `frontend.impl.jac` -- handler bodies

```jac
"""Method bodies for MyApp component."""

impl MyApp.refresh {
    tasks = await get_tasks();
}

impl MyApp.do_login(user: str, pw: str) {
    ok = await jacLogin(user, pw);
    if ok {
        logged_in = True;
        await refresh();
    }
}

impl MyApp.do_add_task {
    if not draft.strip() { return; }
    new_task = await add_task(draft.strip());
    tasks = tasks + [new_task];            # replace, don't mutate
    draft = "";
}
```

Inside `impl MyApp.method` bodies, you have the full component scope: access `has` fields by name, call other methods, `await` server imports.

### Common mistakes in this layout

| Symptom                                      | Cause                                                               | Fix                                                                          |
|----------------------------------------------|---------------------------------------------------------------------|------------------------------------------------------------------------------|
| `{"error": "Client function 'app' not found"}` | Forgot the `to cl:` wrapper in `main.jac`                          | Add the wrapper with `import from frontend { MyApp }` + `def:pub app`        |
| Circular import error                         | Used `include frontend;` or `import from frontend` at module scope   | Use `to cl: import from frontend { MyApp }` (codespace-scoped)               |
| `E2016 Cannot provide implementation...`      | `app` name collision between `main.jac` wrapper and frontend file    | Rename the frontend component (e.g., `MyApp`); keep wrapper named `app`      |
| Blank page, no errors                         | Component name is snake_case (`<linkedin_app/>`)                     | PascalCase: `def:pub LinkedInApp` + `<LinkedInApp/>` (see pitfalls rule 31)   |
| `/styles.css` 404                             | Dev server doesn't serve static files from project root              | Inline CSS via `<style>` or serve via `def:pub` endpoint (pitfalls rule 32)  |
| `impl MyApp.with entry` parse error           | Tried to split a lifecycle hook into impl file                       | Keep `can with entry` inline in `.cl.jac` (pitfalls rule 29)                 |
| Missing impls mysteriously                    | Parse error elsewhere in the `.impl.jac` file                        | `jac check frontend.impl.jac` to find the syntax error                       |

### Static assets caveat

`jac start main.jac` does not serve arbitrary files from the project root. A `<link rel="stylesheet" href="/styles.css"/>` will 404. Options:

1. **Inline** -- small stylesheets as a `glob` string rendered via `<style dangerouslySetInnerHTML={{"__html": MY_CSS}}/>`.
2. **Endpoint** -- larger assets served from a `def:pub` endpoint that reads the file and returns the content.
3. **Use the `jac-client` template** -- `jac create myapp --use client` scaffolds a project with proper static-asset handling.

The `.jac/` cache directory under the project root is regenerated by the compiler; safe to `rm -rf .jac/` to force a clean rebuild if the client shows stale behavior after edits.

---

## § Testing

```jac
test "calculator addition" {
    calc = Calculator();
    calc.add(5.0);
    assert calc.get_result() == 5.0;
}

test "walker reports" {
    root ++> Task(title="A");
    result = root spawn ListTasks();
    assert len(result.reports[0]) == 1;
}
```

Tests can live inline in the `.jac` file, or in a `.test.jac` annex. Run with `jac test <file>`.
