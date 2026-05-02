# Jac Pitfalls -- WRONG vs RIGHT

Load when diagnosing a compile error or when writing code in an unfamiliar area. Each entry: the wrong pattern (what models usually produce), the right pattern, and the reason.

## Syntax -- the Python-assimilation traps

### 1. Missing semicolons

WRONG:

```
x = 5
print(x)
```

RIGHT:

```jac
x = 5;
print(x);
```

Every statement terminates with `;`. Block closers (`}`) do not. This is the single most common failure.

### 2. Indentation instead of braces

WRONG:

```
if x > 5:
    print(x)
```

RIGHT:

```jac
if x > 5 {
    print(x);
}
```

Whitespace is cosmetic. Every block uses braces.

### 3. Python-style imports

WRONG:

```
from os import path
from typing import Callable
import:py typing     # deprecated, removed
```

RIGHT:

```jac
import from os { path }
import from typing { Callable }
```

Python modules and Jac modules use the same syntax. `import:py`, `include:jac`, and other colon-tagged variants are gone. (Note: Jac has a built-in `any` type, so `import from typing { Any }` is no longer needed -- use lowercase `any` directly. See rule 34.)

### 4. Python-style `__init__`

WRONG:

```
obj Foo {
    def __init__(self, x: int) {
        self.x = x;
    }
}
```

RIGHT (auto-init from `has`):

```jac
obj Foo {
    has x: int;
}
```

RIGHT (custom init when needed):

```jac
obj Foo {
    has x: int;
    def init(x: int) {
        super.init();
        self.x = x;
    }
}
```

Constructor is named `init`. `super.init()` must be called explicitly. But prefer `has` with defaults -- it generates the init for you.

### 5. `self` in method signatures

WRONG:

```
obj Foo {
    has x: int;
    def get_x(self) -> int { return self.x; }
}
```

RIGHT:

```jac
obj Foo {
    has x: int;
    def get_x -> int { return self.x; }
}
```

`self` is implicit in `obj`/`node`/`edge`/`walker` method signatures. Still used in the body.

### 6. Instance fields assigned in init instead of declared with `has`

WRONG:

```
obj Foo {
    def init() {
        self.x = 5;
    }
}
```

RIGHT:

```jac
obj Foo {
    has x: int = 5;
}
```

All instance fields **must** be declared with `has`. Dynamic attribute assignment (`obj.new_attr = val`) is an anti-pattern and may break type checking.

### 7. `can` without `with`

WRONG:

```
obj Foo {
    can do_thing -> int { return 42; }
}
```

Error: `Expected 'with' after 'can' ability name (use 'def' for function-style declarations)`.

RIGHT (regular method):

```jac
obj Foo {
    def do_thing -> int { return 42; }
}
```

RIGHT (event ability on a walker):

```jac
walker W {
    can handle with Foo entry { ... }
}
```

`can` is **only** for event-driven abilities with a `with NodeType entry|exit` clause. Regular methods use `def`.

### 8. `enumerate` without tuple parens

WRONG:

```
for i, x in enumerate(items) { ... }
```

RIGHT:

```jac
for (i, x) in enumerate(items) { ... }
```

Any tuple-unpacking for loop needs parentheses around the unpack.

### 9. Python-style `class` when `obj` is idiomatic

Not an error, but not idiomatic:

```jac
class Foo {
    def init(x: int) {
        self.x = x;
    }
}
```

Preferred:

```jac
obj Foo {
    has x: int;
}
```

Use `class` only for Python-specific features: metaclasses, `@property`, `@classmethod` decorators, or when interoperating with Python libraries that require them.

### 10. Backticking built-in references

WRONG:

```
`self.name = "Alice";
`root ++> node;
```

RIGHT:

```jac
self.name = "Alice";
root ++> node;
```

`self`, `super`, `root`, `here`, `visitor`, `init`, `postinit` are built-in references, not keywords that need escaping. Backtick only user-facing keyword collisions like `` `type ``, `` `edge ``.

### 11. Ability headers: `Root` not `` `root ``

WRONG:

```
walker W {
    can start with `root entry { ... }
}
```

RIGHT:

```jac
walker W {
    can start with Root entry { ... }
}
```

In ability headers, use the **type** (`Root`, `Task`, `Employee`) -- capitalized archetype name. The lowercase `root` / `here` / `self` / `visitor` are *instance references* used inside bodies.

## OSP -- graph-specific gotchas

### 12. Walker has no abilities / never dispatches

WRONG:

```
walker W {
    visit [-->];    # bare statements don't belong here
}
```

RIGHT:

```jac
walker W {
    can start with Root entry {
        visit [-->];
    }
    can work with Task entry {
        report here;
    }
}
```

Walkers are declarative. All executable code lives inside `can ... with X entry|exit` abilities.

### 13. `spawn` syntax

RIGHT:

```jac
result = root spawn MyWalker(field=value);
first_report = result.reports[0];
```

Walker fields (`has`) are set by the spawn call (also become the HTTP request body when exposed as an endpoint). `result.reports` is a list in the order `report` statements fired.

### 14. Forgetting `visit [-->]` so the walker never moves

WRONG:

```
walker ListTasks {
    has results: list = [];
    can start with Root entry {
        # missing visit -- walker stays at root, never sees Task nodes
    }
    can collect with Task entry {
        self.results.append(here);
    }
}
```

RIGHT:

```jac
walker ListTasks {
    has results: list = [];
    can start with Root entry {
        visit [-->];
    }
    can collect with Task entry {
        self.results.append(here);
    }
    can done with Root exit {
        report self.results;
    }
}
```

If walker reports come back empty or `visit [-->]` is missing, that's almost always why. Also watch for type mismatches -- `with Task entry` only fires on nodes typed exactly `Task`, not on a parent type.

### 15. `root` syntax -- prefer the bareword

`root` is a special-variable reference (in the same family as `here`, `visitor`, `self`) that resolves directly to the current root instance. Use it as a bareword.

PREFERRED (idiomatic):

```jac
root ++> Task(title="X");
[root-->][?:Task];
```

ALSO ACCEPTED (backward-compat -- still compiles):

<!-- jac-skip -->
```jac
root() ++> Task(title="X");
[root()-->][?:Task];
```

Earlier Jac versions exposed `root` as an ambient builtin function (`def root() -> Root`), so older code uses `root()` everywhere. After the keyword restoration, `root` is the canonical form and `root()` is a callable form that still works. New code should prefer the bareword. Note: assignments to `root` (e.g., `root = something`) are rejected with the same error as assigning to `super`.

## Codespaces -- client/server boundaries

### 16. Client function without `cl` prefix or section header

WRONG (silently creates a **server** function, not a client component):

```
def:pub Greeting(name: str) -> JsxElement {
    return <h1>Hi {name}</h1>;
}
```

RIGHT (prefixed declaration):

```jac
cl def:pub Greeting(name: str) -> JsxElement {
    return <h1>Hi {name}</h1>;
}
```

RIGHT (section header):

```jac
to cl:

def:pub Greeting(name: str) -> JsxElement {
    return <h1>Hi {name}</h1>;
}
```

RIGHT (in a `.cl.jac` file -- whole file is client by default):

```jac
def:pub Greeting(name: str) -> JsxElement {
    return <h1>Hi {name}</h1>;
}
```

### 17. Using React `useState` instead of `has`

Valid but not idiomatic:

```jac
cl import from react { useState }
cl def:pub Counter -> JsxElement {
    (count, set_count) = useState(0);
    return <button onClick={lambda -> None { set_count(count + 1); }}>{count}</button>;
}
```

Preferred:

```jac
cl def:pub Counter -> JsxElement {
    has count: int = 0;
    return <button onClick={lambda -> None { count = count + 1; }}>{count}</button>;
}
```

`has` inside a `cl def:pub` function compiles to `useState`. Assignment (`count = count + 1`) triggers re-render.

### 18. Mutating reactive state

WRONG (UI will not re-render):

```
cl def:pub TodoApp -> JsxElement {
    has todos: list = [];
    async def add_todo {
        todos.append({"text": "new"});   # mutation -- no re-render
    }
}
```

RIGHT:

```jac
cl def:pub TodoApp -> JsxElement {
    has todos: list = [];
    async def add_todo {
        todos = todos + [{"text": "new"}];   # new reference triggers re-render
    }
}
```

Same rule for dicts: `d = {**d, "key": v}`, not `d[key] = v`.

### 19. Dict spread with JS syntax

WRONG:

```
state = {...state, "field": new_value};
merged = {...a, ...b};
```

RIGHT:

```jac
state = {**state, "field": new_value};
merged = {**a, **b};
```

### 20. Event handler lambdas without type annotations (and the `lambda -> None` trap)

Every JSX event prop has a fixed signature: `onClick: Callable[[MouseEvent], NoneType]`, `onChange: Callable[[ChangeEvent], NoneType]`, etc. Handlers **must** take the typed event argument, even if unused. `lambda -> None { ... }` (no args) is rejected by the intrinsic prop types with E1103.

WRONG (missing type annotation):

```
<input onChange={lambda e { name = e.target.value; }} />
```

WRONG (no-arg lambda -- E1103 inside JSX):

```
<button onClick={lambda -> None { handle(); }}>Go</button>
```

```
E1103: Cannot assign <function <lambda>() -> NoneType> to intrinsic prop
'onClick' of type Callable[[MouseEvent], NoneType]
```

RIGHT:

```jac
<input onChange={lambda e: ChangeEvent { name = e.target.value; }} />
<button onClick={lambda e: MouseEvent { handle(); }}>Go</button>
<form onSubmit={lambda e: FormEvent { e.preventDefault(); submit(); }} />
```

Use ambient DOM types -- `ChangeEvent`, `KeyboardEvent`, `FormEvent`, `MouseEvent`, `FocusEvent`, `InputEvent`. No import needed. `lambda -> None { ... }` is valid for non-JSX callbacks (plain function args, setTimeout-style) but never inside a JSX event prop.

### 21. Calling server code from client with plain `import` / `await`

WRONG:

```
import from ..main { get_tasks }       # plain import -- compiler error or silent local call
```

RIGHT (for `def:pub`/`def:priv` functions):

```jac
sv import from main { get_tasks, add_task }

cl def:pub App -> JsxElement {
    async can with entry {
        tasks = await get_tasks();     # transparent HTTP call
    }
}
```

RIGHT (for walkers -- use `spawn`, not `await`):

```jac
sv import from main { AddTask }

cl def:pub App -> JsxElement {
    async def add(text: str) {
        result = root spawn AddTask(title=text);
        new_task = result.reports[0];
    }
}
```

`sv import` is how client code references server symbols. The compiler generates HTTP stubs automatically. `def:pub` functions are called with `await func(args)`; walkers are called with `root spawn Walker(...)` and read `.reports[0]`.

### 22. JSX `class` vs `className`

WRONG:

```
<div class="container">...</div>
```

RIGHT:

```jac
<div class="container">...</div>
```

**Actually in Jac JSX, `class` works.** Unlike React where `class` is a reserved word forcing `className`, Jac accepts `class` directly in JSX because the compiler handles the translation. Both `class` and `className` work -- the Jac-idiomatic choice is `class` (matches HTML).

### 23. List rendering without `key`

WRONG:

```
{[<div>{t.title}</div> for t in tasks]}
```

RIGHT:

```jac
{[<div key={jid(t)}>{t.title}</div> for t in tasks]}
```

React needs a stable unique `key` on each list child. Use `jid(node)` for graph nodes, or any stable unique field on `obj`s.

## Auth & endpoints

### 24. Manual auth / user filtering with `def:priv`

WRONG (manual filtering -- unnecessary):

```
walker:priv get_my_tasks {
    has user_id: str;
    can fetch with Root entry {
        all_tasks = [-->][?:Task];
        report [t for t in all_tasks if t.owner == self.user_id];
    }
}
```

RIGHT (isolation is automatic):

```jac
walker:priv get_my_tasks {
    can fetch with Root entry {
        report [-->][?:Task];
    }
}
```

With `:priv`, each authenticated user's `root` is already their private graph. No manual user_id filtering.

### 25. Manual request/response parsing

WRONG:

```
walker:pub create_task {
    can create with Root entry {
        body = parse_request_body();     # Not a thing
        title = body["title"];
    }
}
```

RIGHT:

```jac
walker:pub create_task {
    has title: str;                      # becomes request body field automatically
    can create with Root entry {
        here ++> Task(title=self.title);
        report {"ok": True};              # becomes response body
    }
}
```

Walker `has` fields are the request body. `report` values are the response.

### 26. Rolling your own login

WRONG:

```
cl def:pub Login -> JsxElement {
    async def submit { await fetch("/api/login", ...); }   # manual auth
}
```

RIGHT:

```jac
cl import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }

cl def:pub Login -> JsxElement {
    has user: str = "", pw: str = "", err: str = "";
    async def submit {
        ok = await jacLogin(user, pw);
        if not ok { err = "Invalid credentials"; }
    }
}
```

## Impl files and organization

### 27. A single syntax error in `.impl.jac` silently empties the whole file

If you edit an `.impl.jac` file and compile-time implementations go missing, a parse error somewhere in that file has zero'd out **every** `impl` block in it. Run `jac check` on the impl file to find the bad syntax; otherwise you'll chase ghost "method not implemented" errors.

### 28. Declaration/implementation split

Declaration file (`calculator.jac`):

```jac
obj Calculator {
    has result: float = 0.0;
    def add(x: float) -> float;       # declaration -- ends with `;`, no body
}
```

Implementation file (`calculator.impl.jac`):

```jac
impl Calculator.add(x: float) -> float {
    self.result += x;
    return self.result;
}
```

Implementations reference `impl Archetype.method` -- the archetype must already be declared.

### 29. Lifecycle hooks cannot be split into `.impl.jac`

`impl Component.with entry { ... }` is a **parse error**. Only named `def` / `can` bodies can be moved to an impl file. Anonymous abilities (lifecycle hooks, including `async can with entry`, `can with exit`, `can with [deps] entry`) must stay inline in the declaration.

WRONG (does not parse):

```
# In frontend.impl.jac
impl app.with entry {
    data = await fetch_data();
}
```

RIGHT -- inline the hook in the declaration file:

```jac
# In frontend.cl.jac
def:pub app -> JsxElement {
    has data: list = [];

    async can with entry {                    # STAYS HERE -- don't impl out
        data = await fetch_data();
    }

    async def refreshData;                    # named -- can go to .impl.jac
    async def addItem(x: str);                # named -- can go to .impl.jac
}
```

```jac
# In frontend.impl.jac
impl app.refreshData {
    data = await fetch_data();
}

impl app.addItem(x: str) {
    data = data + [x];
}
```

## Full-stack / client-side runtime traps

These three classes of bug **compile clean** under `jac check`. The validate-before-present loop won't catch them -- recognize them by symptom.

### 30. Stale reactive closures inside `async can with entry`

The most expensive bug type in client code. `has` fields in a `cl` component compile to React `useState`, and **assignments to them are scheduled for the next render, not applied immediately**. Inside the same block, branching on the value you just assigned reads the *prior* value captured in the closure.

WRONG (logic runs against stale value):

```
async can with entry {
    logged_in = jacIsLoggedIn();     # schedules a setState
    if logged_in {                    # reads the captured initial value (False)
        await refresh_all();          # never fires on reload
    }
}
```

What this compiles to in JS (roughly):

```
useEffect(() => {
    (async () => {
        setLoggedIn(isLoggedIn());
        loggedIn && await refresh_all();   // `loggedIn` is the captured initial value
    })();
}, []);
```

RIGHT -- branch on a local variable, not the `has` field:

```jac
async can with entry {
    is_auth = jacIsLoggedIn();       # local -- immediate
    logged_in = is_auth;             # schedule render update
    if is_auth {                     # use the local
        await refresh_all();
    }
}
```

Rule: **any branch or computation based on a value you just assigned to a `has` field must use a local variable for that decision**. The `has` field is only for the render pass.

### 31. JSX component tags must be PascalCase

A `def:pub` function whose name starts lowercase and is referenced as a JSX tag (`<my_widget/>`) renders as a **literal HTML element**, not a component. React's JSX transform treats lowercase tags as `div`-like intrinsics and uppercase as component references. There is **no compile warning** -- the page just renders a blank `<my_widget></my_widget>` in the DOM.

WRONG (silent failure -- blank panel in browser):

```
# In frontend.cl.jac
def:pub linkedin_app -> JsxElement { return <div>...</div>; }

# In main.jac
to cl:
import from frontend { linkedin_app }
def:pub app -> JsxElement { return <linkedin_app/>; }   # renders as <linkedin_app></linkedin_app>
```

RIGHT:

```jac
# In frontend.cl.jac
def:pub LinkedInApp -> JsxElement { return <div>...</div>; }

# In main.jac
to cl:
import from frontend { LinkedInApp }
def:pub app -> JsxElement { return <LinkedInApp/>; }
```

Snake_case is idiomatic Jac for most identifiers, but component functions referenced in JSX are the exception: **PascalCase always**. Regular `def` / `def:pub` functions that are *called* (not JSX-referenced) can stay snake_case.

### 32. Static assets are not served by `jac start`

`<link rel="stylesheet" href="/styles.css"/>` **404s** under `jac start` -- the dev server does not expose arbitrary files from the project root. For a small stylesheet, inline it. For larger assets, wire a `def:pub` endpoint that returns the content.

WRONG (404 at runtime):

```
def:pub app -> JsxElement {
    return <html>
        <head><link rel="stylesheet" href="/styles.css"/></head>
        <body>...</body>
    </html>;
}
```

RIGHT (inline for small stylesheets -- use triple-quoted strings for multi-line CSS):

```jac
glob APP_CSS: str = """
    .container { max-width: 900px; margin: 40px auto; padding: 20px; }
    .btn { padding: 8px 16px; background: #0a66c2; color: white; border: none; }
    .post { padding: 12px; border: 1px solid #eee; border-radius: 6px; }
""";

def:pub app -> JsxElement {
    return <div>
        <style dangerouslySetInnerHTML={{"__html": APP_CSS}}/>
        ...content...
    </div>;
}
```

Single-quoted strings (`"..."`) cannot span newlines and trigger E0100 (`unterminated string literal`) on the second line. Use `"""..."""` for any multi-line literal -- CSS, prompts, embedded JSON, etc. Same rule as Python.

RIGHT (endpoint for larger assets):

```jac
def:pub styles_css -> str {
    with open("styles.css") as f {
        return f.read();
    }
}
# Then reference: <link rel="stylesheet" href="/function/styles_css"/>
```

This also affects images, fonts, and any other static file. The `jac-client` project scaffolding handles assets for you -- plain `jac start main.jac` without the client template doesn't.

In a `jac create myapp --use client` project, files placed in the project's `assets/` directory **are** served via the Vite dev server's `/assets/*` proxy (post-PR #5661), so `<img src="/assets/logo.png"/>` works there. That path is specific to the scaffolded layout; ad-hoc `.jac` scripts run with bare `jac start` still need the inline-or-endpoint approach above.

### 33. Untyped `list` / `dict` gives `Unknown` element type

Passing a bare `list` through a component prop and indexing into its elements returns `Unknown` for the type-checker, which then refuses to assign into typed params.

WRONG:

```
def:pub UserList(users: list) -> JsxElement {
    return <div>
        {[<button onClick={lambda e: MouseEvent { send_to(u["username"]); }}>...</button> for u in users]}
    </div>;
}
# E1053: Cannot assign <Unknown> to parameter 'u' of type str
```

RIGHT -- use a more specific type:

```jac
def:pub UserList(users: list[dict]) -> JsxElement { ... }
```

Or if the element shape varies and you genuinely need flexibility:

```jac
def:pub UserList(users: list[any]) -> JsxElement { ... }
```

Prefer `list[dict]` over `list[any]` -- the stricter type catches more bugs and works fine for server-returned JSON objects.

### 34. The "any" type -- use lowercase `any`, not `typing.Any`

In Jac, **lowercase `any` is the canonical "any value" type annotation**. It's a built-in -- no import needed. The Python built-in `any()` *function* is accessed via the backtick-escaped `` `any `` form when needed as a callable.

RIGHT:

```jac
def:pub Callback(on_change: any) -> JsxElement { ... }

def takes_any(x: any) -> any {
    return x;
}
```

WRONG (no longer needed -- Jac's `any` is built-in):

```
import from typing { Any }
def:pub Callback(on_change: Any) -> JsxElement { ... }
```

Refer to Python's built-in `any()` function with backticks when you need the callable:

```jac
result = `any([True, False, False]);   # backticked: the built-in function
```

For callback-prop patterns where you want stronger typing than `any`, prefer an explicit `Callable[[...], ReturnType]`:

```jac
import from typing { Callable }

def:pub Callback(on_change: Callable[[str], None]) -> JsxElement { ... }
```

Note: earlier Jac versions exposed `any` only as the Python built-in function and required `Any` from `typing` for the type. Modern Jac (post-#5588 / #5689) treats lowercase `any` as the type by default, so historical examples that import `Any` are deprecated style -- they still work but are unnecessary.

### 35. Filter-expression tautology from shadowed names (W3040)

When a `[?:Type, x == y]` filter has a name on the right-hand side that matches a node field, the RHS silently rebinds to the field rather than the enclosing-scope variable you meant. The comparison becomes `field == field`, always true.

Modern Jac emits **W3040** at compile time:

```
file.jac, line 11, col 41: Filter comparison 'to_user == to_user' is always
true -- both sides resolve to the same node field [filter-compare-tautology]
```

WRONG (compiles with W3040 warning, but the filter is a no-op):

```
to_user = "alice";
tasks = [root-->][?:Task, to_user == to_user];   # always true
```

RIGHT -- rename the local so it doesn't shadow the field:

```jac
target_user = "alice";
tasks = [root-->][?:Task, to_user == target_user];
```

Treat W3040 as a hard error in your own code -- silently-tautological filters mean "show everything that happens to be a Task," which usually isn't what the developer intended.

### 36. `Type | None` annotation on find-in-loop variables

A common pattern: search a graph (or a list) for the node whose field matches some target, capture it in a variable, then act on it. If you initialize with `None` and reassign inside a loop, the type checker locks the variable's type to whatever it inferred from the first assignment -- usually `None` -- and rejects every subsequent edge-connection or method call with `E1096` / `E1097` / `E1030`.

WRONG:

```
def:priv find_friend(target_username: str) -> Profile {
    target = None;                                # inferred as None
    for r in allroots() {
        for p in [r-->[?:Profile]] {
            if p.username == target_username {
                target = p;                       # checker sees this as None | Profile
            }
        }
    }
    target ++> some_edge;                         # E1096: connection operand must be a node
}
```

The checker can't prove `target` is non-`None` at the use site, and worse, the inferred type from the loop body fights the original `None`.

RIGHT -- explicit `Type | None` annotation, then narrow with `is not None`:

```jac
def:priv find_friend(target_username: str) -> Profile | None {
    target: Profile | None = None;
    for r in allroots() {
        for p in [r-->[?:Profile]] {
            if p.username == target_username {
                target = p;
            }
        }
    }
    if target is not None {
        target ++> some_edge;                     # narrowed to Profile, ops work
    }
    return target;
}
```

Three rules to internalize:

1. **Always declare `T | None`** on any variable that starts unset and may be assigned a `T` inside a loop or conditional.
2. **Always narrow with `is not None`** (or `is None` and early-return) before operating on the variable. The checker only narrows under explicit guards.
3. **Return `T | None`** from helper functions with this shape -- callers can then narrow once at the call site.

This pattern is common in cross-user lookups (`find_profile_by_username`, `find_post_by_id`), feed filters, and any "find one matching node" helper.

### 37. Logout doesn't reset status / message / error fields

In a `cl` component, logout typically resets data fields (`tasks = []`, `feed = []`) but it's easy to forget the *status* fields -- error messages, success notifications, "saving..." flags. Reactive state lingers across logout/login because nothing assigned to those `has` fields between sessions.

WRONG (incomplete cleanup):

```
async def do_logout {
    await jacLogout();
    logged_in = False;
    feed = [];
    profile_data = {"username": "", "name": "", "headline": ""};
    # forgot: profile_msg, post_err, connection_msg, auth_err, busy_target, ...
}
```

Result: a previous session's "Profile saved!" or "Connection request sent" briefly flashes after a fresh signup.

RIGHT (sweep every status field):

```jac
async def do_logout {
    await jacLogout();
    logged_in = False;
    feed = [];
    profile_data = {"username": "", "name": "", "headline": ""};

    # Status / message / error / busy fields -- reset every one
    profile_msg = "";
    post_err = "";
    connection_msg = "";
    auth_err = "";
    busy_target = "";
    profile_saving = False;
    profile_polishing = False;
}
```

Rule of thumb: if your component has a `has` field whose value is set by a handler in response to user action, reset it on logout. Treat the logout handler as a full-component reinitialization, not just a "clear my data" action.

### 38. `datetime.datetime.now()` fails type-checking in function bodies

Calling `datetime.datetime.now().strftime(...)` inside a `def` body triggers E1031 because the checker infers the `now()` return as `Self` and can't resolve `.strftime()` on it. The `has`-field default position works; function-body position doesn't.

WRONG:

```
import datetime;

def now_ts -> str {
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S");
    # error[E1031]: Cannot access attribute "strftime" for type "Self"
}
```

RIGHT (use `time` stdlib):

```jac
import time;

def now_ts -> str {
    return time.strftime("%Y-%m-%d %H:%M:%S");
}
```

Alternatively, type the intermediate variable explicitly:

```jac
import from datetime { datetime }

def now_ts -> str {
    n: datetime = datetime.now();     # narrows the Self inference
    return n.strftime("%Y-%m-%d %H:%M:%S");
}
```

## Error-code quick match

| Code         | Usually means                                                                     |
|--------------|------------------------------------------------------------------------------------|
| E0201        | Undefined name -- missing import, or symbol from wrong codespace                    |
| E0407        | `can` used without `with` -- use `def` or add `with Type entry`                     |
| E1002        | Cannot return `NoneType` from `-> T` -- widen return to `T \| None`                 |
| E1031        | Cannot access attribute on `Self` -- Python stdlib typeshed issue, see rule 38      |
| E1096/E1097  | Connection operand must be a node -- usually a `None`-initialized find-in-loop var (rule 36) |
| E1053        | Cannot assign `<Unknown>` to typed param -- untyped `list` / `dict`, see rule 33    |
| E1100        | Type not assignable -- callback signature mismatch on JSX intrinsic prop, or other type mismatch |
| W3040        | Filter comparison tautology from shadowed names (`[?:T, x == x]` always true)       |
| E1103        | Cannot assign to intrinsic JSX prop -- `lambda -> None` in event handler (rule 20)  |
| E2016        | Method already has body -- usually a name collision across files, see paradigms.md  |
| W0064        | Use `to cl:` section header instead of braced `cl { ... }` at module scope         |
| W1050        | Unknown intrinsic JSX element -- `<style>`, `<link>`, etc. warn but may still work  |
| W1051        | Expression type could not be resolved -- often spurious on `sem` declarations       |
| W2003        | Defined but never used -- harmless for unused lambda params                         |
| W3037        | `-> None` is unnecessary on a lambda -- drop the annotation                          |

For error codes not listed here, run `jac check <file>` with the `-v` flag (if supported) or consult the compiler output directly. Diagnose against the WRONG/RIGHT pairs in this file before speculating at a fix.
