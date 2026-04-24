# State Management

Interactive applications need to track and respond to changing data -- a counter incrementing, a list of items growing, a form being filled out. In Jac's client-side code, state management uses the `has` keyword inside component functions to declare reactive variables. Each `has` field compiles to a reactive signal cell: you read and write it like a plain field, and any component or effect that read it automatically re-runs when the value changes.

This tutorial covers declaring reactive state, handling user input, sharing state between components, and managing complex state with effects and derived values.

> **Prerequisites**
>
> - Completed: [React-Style Components](components.md)
> - Time: ~30 minutes

---

## Reactive State with `has`

Inside `cl { }` blocks, `has` creates reactive state. Declaring `has count: int = 0;` inside a component function creates a stateful variable that persists across re-renders and triggers a UI update whenever its value changes:

```jac
to cl:

def:pub Counter() -> JsxElement {
    has count: int = 0;  # Reactive state

    return <div>
        <p>Count: {count}</p>
        <button onClick={lambda -> None { count = count + 1; }}>
            Increment
        </button>
    </div>;
}
```

**How it works:**

- `has count: int = 0` compiles to `const count = useSignal(0)` (Preact Signals)
- Reads of `count` in JSX, conditions, and arguments compile to `count.value`, which is a live read -- always returns the most recent value
- Assignments like `count = count + 1` become `count.value = count.value + 1`
- Any component or effect that read `count.value` is automatically subscribed and re-runs when the signal changes

---

## Multiple State Variables

```jac
to cl:

def:pub Form() -> JsxElement {
    has name: str = "";
    has email: str = "";
    has submitted: bool = False;

    def handle_submit() -> None {
        print(f"Submitting: {name}, {email}");
        submitted = True;
    }

    if submitted {
        return <p>Thanks, {name}!</p>;
    }

    return <form>
        <input
            value={name}
            onChange={lambda e: ChangeEvent { name = e.target.value; }}
            placeholder="Name"
        />
        <input
            value={email}
            onChange={lambda e: ChangeEvent { email = e.target.value; }}
            placeholder="Email"
        />
        <button
            type="button"
            onClick={lambda -> None { handle_submit(); }}
        >
            Submit
        </button>
    </form>;
}
```

---

## Complex State (Objects/Lists)

```jac
to cl:

def:pub TodoApp() -> JsxElement {
    has todos: list = [];
    has input_text: str = "";

    def add_todo() -> None {
        if input_text {
            todos = todos + [{"id": len(todos), "text": input_text}];
            input_text = "";
        }
    }

    def remove_todo(id: int) -> None {
        todos = [t for t in todos if t["id"] != id];
    }

    return <div>
        <input
            value={input_text}
            onChange={lambda e: ChangeEvent { input_text = e.target.value; }}
        />
        <button onClick={lambda -> None { add_todo(); }}>Add</button>

        <ul>
            {[
                <li key={todo["id"]}>
                    {todo["text"]}
                    <button onClick={lambda -> None { remove_todo(todo["id"]); }}>
                        X
                    </button>
                </li>
                for todo in todos
            ]}
        </ul>
    </div>;
}
```

**Important:** For lists and objects, create new references:

- `todos = [...todos, newItem]` (spread to new list)
- `todos = [t for t in todos if condition]` (filter to new list)

---

## useEffect - Side Effects

### Automatic Effects with `can with entry/exit`

Similar to how `has` automatically generates `useState`, you can use `can with entry` and `can with exit` to automatically generate `useEffect` hooks:

```jac
to cl:

def:pub DataFetcher() -> JsxElement {
    has data: list = [];
    has loading: bool = True;

    # Run once on mount - async effects are wrapped in IIFE automatically
    async can with entry {
        result = await some_async_operation();
        data = result;
        loading = False;
    }

    if loading {
        return <p>Loading...</p>;
    }

    return <ul>
        {[<li key={item.id}>{item.name}</li> for item in data]}
    </ul>;
}
```

### Effects React to Signal Reads Automatically

Because `has` fields are signals, an effect re-runs whenever any signal it reads inside its body changes. You don't need (and shouldn't write) a dependency list -- the tracking is automatic and can't go out of sync with the body:

```jac
to cl:

def:pub SearchResults() -> JsxElement {
    has query: str = "";
    has results: list = [];

    # Runs at mount AND whenever `query` changes, because the body reads it
    async can with entry {
        if query {
            results = await search_api(query);
        }
    }

    return <div>
        <input
            value={query}
            onChange={lambda e: ChangeEvent { query = e.target.value; }}
        />
        <ul>
            {[<li>{r}</li> for r in results]}
        </ul>
    </div>;
}
```

> **Note:** The older `can with [deps] entry` form still parses but its dependency list is ignored (signals auto-track), and the compiler emits a `W5033` deprecation warning. Remove the brackets to silence it.
>
> **Escape hatch:** If you want to read a signal inside an effect *without* subscribing to it (useful for logging or when you only want to read the current value once), use `.peek()` instead of the plain field read: `print(query.peek())`.

### Cleanup Effects

Use `can with exit` for cleanup logic (runs on unmount):

```jac
to cl:

def:pub Timer() -> JsxElement {
    has seconds: int = 0;

    # Setup interval on mount
    can with entry {
        intervalId = setInterval(lambda -> None {
            seconds = seconds + 1;
        }, 1000);
    }

    # Cleanup on unmount
    can with exit {
        clearInterval(intervalId);
    }

    return <p>Seconds: {seconds}</p>;
}
```

### Manual useEffect

The `can with entry/exit` syntax above is the idiomatic approach and should be preferred. However, you can also use `useEffect` manually by importing from React -- this is useful for complex patterns involving `useRef` or `useCallback`:

```jac
to cl:

import from react { useEffect }

def:pub DataFetcher() -> JsxElement {
    has data: list = [];

    useEffect(lambda -> None {
        fetch_data();
    }, []);

    return <div>...</div>;
}
```

---

## useContext - Global State

### Creating Context

```jac
to cl:

import from react { createContext, useContext }

# Create context
glob AppContext = createContext(None);

# Provider component
def:pub AppProvider(props: dict) -> JsxElement {
    has user: any = None;
    has theme: str = "light";

    value = {
        "user": user,
        "theme": theme,
        "setUser": lambda u: any -> None { user = u; },
        "setTheme": lambda t: str -> None { theme = t; }
    };

    return <AppContext.Provider value={value}>
        {props.children}
    </AppContext.Provider>;
}

# Consumer component
def:pub UserDisplay() -> JsxElement {
    ctx = useContext(AppContext);

    if ctx.user {
        return <p>Welcome, {ctx.user.name}!</p>;
    }
    return <p>Not logged in</p>;
}

def:pub ThemeToggle() -> JsxElement {
    ctx = useContext(AppContext);

    return <button onClick={lambda -> None {
        ctx.setTheme("dark" if ctx.theme == "light" else "light");
    }}>
        Toggle Theme ({ctx.theme})
    </button>;
}

def:pub app() -> JsxElement {
    return <AppProvider>
        <UserDisplay />
        <ThemeToggle />
    </AppProvider>;
}
```

---

## Custom Hooks

Create reusable state logic:

```jac
to cl:

import from react { useEffect }

# Custom hook
def use_local_storage(key: str, initial_value: any) -> tuple {
    has value: any = initial_value;

    # Load from localStorage on mount
    useEffect(lambda -> None {
        stored = localStorage.getItem(key);
        if stored {
            value = JSON.parse(stored);
        }
    }, []);

    # Save to localStorage when value changes
    useEffect(lambda -> None {
        localStorage.setItem(key, JSON.stringify(value));
    }, [value]);

    return (value, lambda v: any -> None { value = v; });
}

def:pub Settings() -> JsxElement {
    (theme, set_theme) = use_local_storage("theme", "light");

    return <div>
        <p>Current theme: {theme}</p>
        <button onClick={lambda -> None { set_theme("dark"); }}>
            Dark
        </button>
        <button onClick={lambda -> None { set_theme("light"); }}>
            Light
        </button>
    </div>;
}
```

---

## State Patterns

### Loading State Pattern

```jac
to cl:

def:pub DataComponent() -> JsxElement {
    has data: any = None;
    has loading: bool = True;
    has error: str = "";

    # ... fetch data ...

    if loading {
        return <div className="spinner">Loading...</div>;
    }

    if error {
        return <div className="error">{error}</div>;
    }

    return <div>{data}</div>;
}
```

### Form State Pattern

```jac
to cl:

def:pub ContactForm() -> JsxElement {
    has form_data: dict = {
        "name": "",
        "email": "",
        "message": ""
    };
    has errors: dict = {};
    has submitting: bool = False;

    def update_field(field: str, value: str) -> None {
        form_data = {**form_data, field: value};
    }

    def validate() -> bool {
        new_errors = {};
        if not form_data["name"] {
            new_errors["name"] = "Name is required";
        }
        if "@" not in form_data["email"] {
            new_errors["email"] = "Invalid email";
        }
        errors = new_errors;
        return len(new_errors) == 0;
    }

    def handle_submit() -> None {
        if validate() {
            submitting = True;
            # ... submit form ...
        }
    }

    return <form>
        <input
            value={form_data["name"]}
            onChange={lambda e: ChangeEvent { update_field("name", e.target.value); }}
        />
        {errors.get("name") and <span className="error">{errors["name"]}</span>}
    </form>;
}
```

---

## Key Takeaways

| Concept | Jac Syntax | Compiles to |
|---------|------------|-------------|
| State variable | `has count: int = 0` | `const count = useSignal(0)` |
| Read state | `count` | `count.value` (live, always current) |
| Update state | `count = count + 1` | `count.value = count.value + 1` |
| Read without subscribing | `count.peek()` | `count.peek()` |
| Effect on mount / reactive to reads | `can with entry { ... }` | `useSignalEffect(() => { ... })` |
| Cleanup on unmount | `can with exit { ... }` | `useEffect(() => cleanup, [])` |
| Global state | `useContext(Ctx)` | Same |

> The old `can with [dep] entry` (explicit deps array) form is deprecated. Signals auto-track reads inside the effect body, so the list is redundant. The compiler emits `W5033` to flag this.

---

## Next Steps

- [Backend Integration](backend.md) - Fetch data from walkers
- [Authentication](auth.md) - Add user login
