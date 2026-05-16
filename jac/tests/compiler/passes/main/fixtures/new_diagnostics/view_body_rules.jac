"""Fixture: `view` body rule violations caught by ViewLowerPass.

Exercises the view_body_check diagnostics:
  - E2019: a `view` cannot `return` a value.
  - E2020: bare `return;` is not allowed inside a template loop.
  - E2021: `break` / `skip` are not allowed inside a template loop.
  - W2019: a `while` loop renders JSX without a `key` attribute.
"""

view ValueReturn(x: int) {
    <p>before</p>
    return x + 1;
}

view ReturnInLoop(items: list) {
    for it in items {
        <li key={it}>{it}</li>
        return;
    }
}

view BreakInLoop(items: list) {
    for it in items {
        <li key={it}>{it}</li>
        break;
    }
}

view KeylessWhile(n: int) {
    while n > 0 {
        <span>tick</span>
    }
}
