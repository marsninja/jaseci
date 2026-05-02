---
name: jac-write
description: Expert authoring of Jac-language code (.jac files). Use whenever writing, editing, explaining, or debugging Jac, Jaseci, jaclang, byllm, jac-client, or jac-scale code. Jac looks like Python but is NOT Python -- this skill prevents Python-assimilation errors (missing semicolons, indentation blocks, __init__, self-in-obj-method-params, import:py, from-X-import-Y, .append() mutation in cl components, `can` without a `with` clause). Fires on any .jac file edit, any paste of jac CLI output, any request mentioning Jac/Jaseci/jaclang, and any .jac code block in conversation. Enforces a mandatory compile-before-present loop using the `jac` CLI.
---

# Writing Jac

Jac is a full-stack language that compiles to Python bytecode (server), JavaScript (client), and native binaries -- from a single file. It extends Python with three paradigms: **codespaces** (sv/cl/na), **Object-Spatial Programming** (nodes/edges/walkers/root), and **Meaning-Typed Programming** (`by llm` + `sem`).

This skill teaches you to write Jac that compiles on the first try. Read this file completely before emitting any Jac code. For deep dives load the companion files on demand:

- **`pitfalls.md`** -- WRONG vs RIGHT for every common trap. Load when diagnosing compile errors or when a user reports "my Jac won't run."
- **`paradigms.md`** -- canonical patterns for OSP (walkers), MTP (by llm), and codespaces (sv/cl). Load when the task involves graph traversal, AI delegation, or full-stack client/server work.
- **`examples/walker.jac`** -- accumulator / counter / search-disengage walker patterns.
- **`examples/by_llm.jac`** -- enum-constrained and structured-output AI functions.
- **`examples/mini_todo.jac`** -- canonical one-file full-stack app (nodes + def:pub + by llm + cl component).

## The reset -- Jac is NOT Python

Before writing one line, internalize these ten rules. Most failures trace back to one of them.

1. **Semicolons terminate every statement.** `x = 5;` `return x;` `print(x);`. No exceptions except block-closing braces.
2. **Braces, not indentation.** `if x > 0 { print(x); }` -- whitespace is cosmetic.
3. **`has` declares instance fields; `self` is implicit.** Never write `def __init__(self, x)` then `self.x = x`. Instead: `has x: int;` at class level.
4. **`init` not `__init__`.** Jac's constructor is named `init`, and it calls `super.init()` explicitly if defined.
5. **`def` for methods; `can` ONLY for event abilities.** `can name with NodeType entry { ... }`. If you write `can` without `with`, the compiler rejects it. Plain methods use `def`.
6. **No `self` in `obj`/`node`/`edge`/`walker` method signatures.** It's always available in the body. Python-style `def foo(self: Foo, x)` is an error.
7. **Imports use `import from MODULE { NAMES }`.** Never `from module import name`, never `import:py`, never the old colon-tagged variants. Python modules import the same way.
8. **Prefer `obj` over `class`.** `obj` auto-generates `__init__`, `__eq__`, `__repr__` from `has` fields. Use `class` only for Python-specific features (metaclasses, `@property`, etc.) that can't cross codespace boundaries.
9. **In `cl` (client) components, never mutate reactive state.** `items.append(x)` and `dict[k] = v` will **not** re-render. Use `items = items + [x]` and `dict = {**dict, k: v}`.
10. **Ability headers use the archetype name, capitalized.** `with Root entry`, `with Task entry`. The lowercase built-ins (`root`, `here`, `self`, `visitor`) are *references* used in bodies, not type names in headers. Never backtick them.

## The workflow -- compile before presenting

**This is mandatory.** Do not present Jac code to the user until it passes `jac check`. Jac's type system is strict enough that a compile pass eliminates most latent bugs.

1. Write the code.
2. Save to a file (use the project's file if editing, or `/tmp/check.jac` for a throwaway).
3. Run `jac check <file>` via Bash. Type-only check; fast.
4. For a full test, run `jac <file>` (executes the `with entry` block) or `jac start <file>` (starts the HTTP server).
5. If errors appear:
   - Identify the error code (e.g. `E0407`, `W1051`).
   - Match against the pitfall table in `pitfalls.md`.
   - Fix and re-run from step 3.
6. Only present to the user after a clean `jac check` pass.

**A single parse error in an `.impl.jac` file silently produces zero body implementations for the whole file** -- always compile after editing impl blocks.

For full-stack apps, also verify the server boots. Two reliable smoke-tests:

- `curl -s http://localhost:8000/` returns a JSON catalog of mounted endpoints/walkers.
- The client component renders at `http://localhost:8000/cl/<name>` -- a `cl def:pub app -> JsxElement { ... }` declaration is served at `/cl/app`, `cl def:pub MyPage` at `/cl/MyPage`, etc.

There is no built-in `/docs` Swagger route on plain `jac start`; reach for the `jac-client` scaffold (`jac create myapp --use client`) if you need a generated API explorer. For client-only code, the compile pass is usually sufficient.

## Syntax essentials (inline -- enough for simple code)

### Types

Scalar: `str`, `int`, `float`, `bool`. Collections: `list`, `list[T]`, `dict`, `dict[K, V]`, `tuple`, `set`. Special: `None`, `any`. Unions: `str | None`. Type annotations are **required** on function params and return types, and on `has` fields.

For "any value," use lowercase **`any`** as the type annotation -- it's a Jac built-in, no import needed. The Python `any()` *function* (the one that takes an iterable and returns `bool`) is accessed via the backtick-escaped `` `any `` form when you need it as a callable. Prefer concrete types where possible; reach for `any` only for truly opaque data (e.g., callback props of unknown shape).

### Variables and entry blocks

```jac
with entry {
    name: str = "Jac";        # typed
    count = 42;                # inferred
    greeting = f"Hello {name}";
    print(greeting);
}
```

Top-level code must live in a `with entry { }` block. A file can have multiple; they run in declaration order. `with entry:__main__ { }` runs only when the file is executed directly (not imported).

### Functions

```jac
def greet(name: str) -> str {
    return f"Hello, {name}!";
}

def no_return() {
    print("void");             # -> None is implicit
}

def:pub public_endpoint(x: int) -> dict { return {"x": x}; }   # HTTP endpoint
def:priv per_user_endpoint() -> list { return [root-->]; }   # auth-required, per-user root
```

`def:pub` marks a function as an HTTP endpoint when served with `jac start`. `def:priv` requires authentication and gives each user their own `root`.

### Objects, nodes, edges, enums

```jac
obj Point {
    has x: float,
        y: float;

    def magnitude -> float {
        return (self.x ** 2 + self.y ** 2) ** 0.5;
    }
}

node Task {
    has title: str,
        done: bool = False;
}

edge Scheduled {
    has time: str,
        priority: int = 1;
}

enum Category { WORK, PERSONAL, SHOPPING, HEALTH, OTHER }
```

`obj` = data container (not persistent). `node` = graph-resident data (persistent when connected to `root`). `edge` = typed connection between nodes. `enum` = constrained value set -- critical for constraining `by llm()` output.

### Imports

```jac
import os;                             # whole module
import datetime as dt;                  # with alias
import from math { sqrt, pi }          # selected names from a module
import from .sibling { helper }         # relative
import from byllm.lib { Model }         # third-party PyPI/Jac packages -- same syntax
```

### Control flow

```jac
if x > 0 { ... } elif x < 0 { ... } else { ... }

for item in items { ... }
for (i, item) in enumerate(items) { ... }     # tuple unpacking REQUIRES parens
for i = 0 to i < 10 by i += 1 { ... }         # C-style range

while cond { ... }

match value {
    case 0: ...;
    case 1 | 2: ...;
    case x if x > 100: ...;
    case _: ...;
}

try { risky(); } except ValueError as e { ... } finally { ... }
```

### Collections and comprehensions

```jac
xs = [1, 2, 3];
d = {"a": 1, "b": 2};
s = {1, 2, 3};
t = (1, 2);

squares = [x ** 2 for x in xs];
evens = [x for x in xs if x % 2 == 0];
as_map = {k: v for (k, v) in d.items()};
```

### Lambdas

```jac
add = lambda x: int, y: int -> int : x + y;
handler = lambda e: ChangeEvent { text = e.target.value; };    # brace body for multi-statement
void_cb = lambda -> None { count = count + 1; };                # no-arg void -- NON-JSX ONLY
```

**JSX event props are not "no-arg void" handlers.** Intrinsic props like `onClick`, `onChange`, `onSubmit` have fixed signatures that take a typed event argument (`MouseEvent`, `ChangeEvent`, `FormEvent`). Writing `lambda -> None { ... }` inside a JSX prop raises E1103 (`Cannot assign <function <lambda>() -> NoneType> to intrinsic prop 'onClick' of type Callable[[MouseEvent], NoneType]`).

```jac
# WRONG inside JSX -- E1103
<button onClick={lambda -> None { add_task(); }}>Add</button>

# RIGHT -- include a typed event parameter, even if unused
<button onClick={lambda e: MouseEvent { add_task(); }}>Add</button>
<input onChange={lambda e: ChangeEvent { text = e.target.value; }} />
<form onSubmit={lambda e: FormEvent { e.preventDefault(); handle(); }} />
```

Use ambient DOM types -- `ChangeEvent`, `KeyboardEvent`, `FormEvent`, `MouseEvent`, `FocusEvent` -- no import needed. `lambda -> None { ... }` is only correct for non-JSX callbacks (plain function arguments, setTimeout-style hooks).

## The three paradigms (glance)

Full playbooks live in `paradigms.md`. Load it when the task touches any of these in depth.

### Codespaces (where code runs)

```jac
# Server code (default -- no header needed)
node Todo { has title: str; }
def:pub get_todos -> list { return [root-->][?:Todo]; }

to cl:

def:pub app -> JsxElement {
    has todos: list = [];
    async can with entry { todos = await get_todos(); }
    return <div>{[<p key={jid(t)}>{t.title}</p> for t in todos]}</div>;
}
```

`to sv:`, `to cl:`, `to na:` section headers partition a file into codespaces. File extensions set the default (`.cl.jac`, `.sv.jac`, `.na.jac`). The compiler generates the HTTP call, serialization, and routing between codespaces automatically.

### Object-Spatial Programming (graph-native data + walkers)

```jac
node Task { has title: str; }

# Create + connect in one operator
with entry { root ++> Task(title="Learn Jac"); }

# Query the graph -- same filter syntax as lists
tasks = [root-->][?:Task];
pending = [root-->][?:Task, done == False];

# Walkers = mobile computation that visits nodes
walker CountTasks {
    has total: int = 0;
    can start with Root entry { visit [-->]; }
    can count with Task entry { self.total += 1; }
    can finish with Root exit { report self.total; }
}

result = root spawn CountTasks();   # returns {reports: [3]}
```

Nodes reachable from `root` **persist automatically** across process restarts. Each authenticated user gets their own private `root` (via `def:priv` or `walker:priv`). No database, no ORM, no migrations.

### Meaning-Typed Programming (AI via by llm)

```jac
import from byllm.lib { Model }
glob llm = Model(model_name="claude-sonnet-4-20250514");

enum Category { WORK, PERSONAL, SHOPPING, HEALTH }

def categorize(title: str) -> Category by llm();
sem categorize = "Categorize a task based on its title";
```

`by llm()` replaces the function body. The signature (name, param names, types, return type) **is** the prompt. An `enum` return type constrains output to exactly those values; an `obj` return type forces structured output with every field filled. `sem` attaches a semantic hint the compiler includes in the prompt -- use it whenever a type alone doesn't disambiguate (e.g., "cost" without sem could be currency-in-what?).

## Anti-pitfall reminders (top 15 -- full table in pitfalls.md)

1. **`import:py` is dead syntax.** Never emit it. Use `import from X { Y }`.
2. **`def __init__(self, ...)` is wrong.** In `obj`, use `has` fields (auto-init). If you must customize: `def init(x: int) { super.init(); self.x = x; }`.
3. **`self` in method signatures is wrong.** `obj Foo { def bar -> int { return self.x; } }` -- no `self` param.
4. **`items.append(x)` in a `cl` component won't re-render.** Use `items = items + [x]`.
5. **`can do_thing { ... }` without `with` is an error.** Either use `def`, or add `with NodeType entry { ... }`.
6. **`for i, x in enumerate(xs)` is an error.** Parens required: `for (i, x) in enumerate(xs)`.
7. **Dict spread uses `{**d, k: v}`, not `{...d, k: v}`.** Jac is Python-flavored, not JS.
8. **Calling `def:pub` from client: `await func_name()`. Calling walkers: `root spawn Walker()` then read `.reports[0]`.** These are not interchangeable.
9. **`cl import from "..."` for JavaScript/npm runtime; `sv import from ...` to pull server symbols into client code; plain `import` for Python/Jac packages.** Mixing them up produces silent HTTP-vs-local-call confusion.
10. **Walker ability headers use archetype names, not lowercase references.** `with Root entry` not `` with `root entry ``. `Root` is the type; `root` is the instance reference.
11. **JSX component tags must be PascalCase.** `<my_widget/>` renders as a literal HTML element with no component binding -- the app "works" but shows a blank panel. Rename to `MyWidget` and reference as `<MyWidget/>`.
12. **Reactive `has` assignments are scheduled, not immediate.** Inside the same synchronous block, don't branch on a field you just assigned -- use a local variable (see pitfalls.md rule 29). This compiles clean but is wrong at runtime.
13. **`lambda -> None { ... }` is rejected by JSX event props.** All JSX handlers need a typed event parameter: `lambda e: MouseEvent { ... }`, even when the event is unused.
14. **Use lowercase `any` as the type annotation.** It's a Jac built-in; no `import from typing { Any }` needed. Reach for `` `any `` (backticked) only when you need the Python built-in *function*. (Older Jac required capitalized `Any` from `typing`; that's deprecated style now -- still works but unnecessary.)
15. **`impl app.with entry { ... }` doesn't parse.** Lifecycle hooks (`can with entry`, `can with exit`, `can with [deps] entry`) must stay inline in the component's `.cl.jac` declaration -- only named `def`/`can` can be split into an `.impl.jac` file.

## Traps that compile clean but fail at runtime

The `jac check` loop is the skill's primary correctness mechanism, but three classes of bug slip past it. Review this list whenever a `cl` component renders "wrong but not broken":

- **Stale reactive closures** -- reading a `has` field you just assigned in the same `async can with entry` block (`logged_in = jacIsLoggedIn(); if logged_in { ... }`). The compiled JS captures the pre-update value. Use a local: `is_auth = jacIsLoggedIn(); logged_in = is_auth; if is_auth { ... }`.
- **Lowercase JSX component tags** -- no compile warning, but React treats `<my_app/>` as a custom HTML element and skips component binding. Always PascalCase.
- **Static assets the dev server doesn't serve** -- `<link rel="stylesheet" href="/styles.css"/>` 404s under `jac start` unless you wire a `def:pub` endpoint for it. Inline CSS via `<style>{...}</style>` or `dangerouslySetInnerHTML` for small stylesheets.

## Self-check before presenting

Run this checklist mentally on every Jac block before returning it. If any answer is "no" or "unsure," run `jac check` -- do not skip.

- [ ] Every statement ends with `;` (except block-closing `}`).
- [ ] Every block uses `{}`, not indentation.
- [ ] Every instance field is declared with `has` at class level, not assigned in `init`.
- [ ] No `self` appears in any `obj`/`node`/`edge`/`walker` method signature (it's implicit).
- [ ] Every function and `has` field has type annotations.
- [ ] All imports use `import from X { Y }` or `import X;` -- no `import:py`, no `from X import Y`.
- [ ] Any `can` keyword is followed by `with NodeType entry` or `with NodeType exit`.
- [ ] In `cl` components, reactive state (`has`) is replaced via `=`, never mutated.
- [ ] Event handler lambdas in JSX have typed parameters (`lambda e: ChangeEvent { ... }`) -- never `lambda -> None` inside a JSX prop.
- [ ] Any type annotation for "any value" uses lowercase `any` (Jac built-in -- no import). The backticked `` `any `` is reserved for referring to Python's `any()` function.
- [ ] Component functions referenced as JSX tags are PascalCase (`<LinkedInApp/>`, not `<linkedin_app/>`).
- [ ] Inside `async can with entry`, branches on reactive state use a local variable -- not the `has` field you just assigned.
- [ ] I ran `jac check <file>` and it passed.

If the user reports a compile error you can't place, load `pitfalls.md` and match the error message against the WRONG/RIGHT pairs before speculating at fixes.

## When to load more

| Task                                          | Load                             |
|-----------------------------------------------|----------------------------------|
| Graph traversal / walker with accumulator     | `paradigms.md` § OSP + `examples/walker.jac` |
| AI function with structured output            | `paradigms.md` § MTP + `examples/by_llm.jac` |
| Full-stack app with client UI                 | `paradigms.md` § Codespaces + `examples/mini_todo.jac` |
| Authenticated / multi-user                    | `paradigms.md` § Auth |
| Compile error you can't identify              | `pitfalls.md` (search by error code or symptom) |
| Syntax lookup mid-write                       | This file's "Syntax essentials" section |

For anything outside this skill's scope (production deployment, native compilation, advanced walker patterns), consult the upstream docs at https://docs.jaseci.org.
