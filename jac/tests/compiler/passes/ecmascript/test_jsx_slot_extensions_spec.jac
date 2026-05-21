"""Executable spec for the unimplemented #6082 items.

Every test in this file is expected to FAIL until the corresponding
JSX-slot extension lands. The file is a tracker, not a regression
guard -- the failure shape codifies the contract each follow-up PR
must satisfy.

Mapping to issue #6082 items:

  - rec 1.1 / 1.2 / 1.3: item 1 (auto-fragment) priorities 1, 2, 3
  - rec 2:               item 3 (except + awaiting integration)
  - rec 4:               item 5 (static JSX subtree hoisting)
  - rec 6:               item 7 (statement-level JSX in def -> JsxElement)
  - rec 7:               item 8 (Ref[T] ambient + useRef) -- cross-ref #6055
  - rec 8:               item 9 (sv lowering for awaiting) -- cross-ref #6055
  - rec 9:               item 10 (.style.css annex) -- cross-ref #6055
  - rec 10:              item 8 of #6082 (walker progressive frames) -- gated on #6056

Three tests (rec 4, rec 8, rec 10) carry POST-IMPLEMENTATION
TIGHTENING notes for cases where the issue body leaves the contract
underspecified -- those assertions should be sharpened once the
implementer commits to a concrete shape.

The four tests that DO pass on `feat/jsx-slot-extensions` (rec 1.4
W2021 fallback, rec 1.5 keyless-for diagnostic, rec 3 E2024 has-in-slot,
rec 5 prop shorthand) live in `test_slot_extensions.jac` -- this file
contains only the still-failing ones.
"""

import os;
import pytest;
import from pathlib { Path }
import jaclang;
import from jaclang.compiler.passes.ecmascript { EsastGenPass }
import jaclang.compiler.passes.ecmascript.estree as es;
import from jaclang.compiler.passes.ecmascript.es_unparse { es_to_js }
import from jaclang.jac0core.program { JacProgram }

glob JAC_ROOT = str(Path(jaclang.__file__).parent.parent),
     SLOT_EXT = os.path.join(
         JAC_ROOT,
         "tests",
         "compiler",
         "passes",
         "ecmascript",
         "fixtures",
         "slot_extensions"
     );

"""Compile a fixture to ESTree and assert no errors were emitted."""
def compile_to_esast(filename: str) -> es.Program {
    path = os.path.join(SLOT_EXT, filename);
    prog = JacProgram();
    ir = prog.compile(file_path=path, no_cgen=True);
    assert not prog.errors_had , (
        f"Compilation errors in {filename}: " + str([str(e) for e in prog.errors_had])
    );
    es_pass = EsastGenPass(ir_in=ir, prog=prog);
    return es_pass.ir_out.gen.es_ast;
}

"""Compile a fixture, returning the JacProgram so diagnostics can be inspected."""
def compile_for_diag(filename: str) -> JacProgram {
    path = os.path.join(SLOT_EXT, filename);
    prog = JacProgram();
    prog.compile(file_path=path);
    return prog;
}

"""True iff `program` emitted a diagnostic with the given code."""
def has_code(program: JacProgram, code: str, in_warnings: bool = False) -> bool {
    alerts = program.warnings_had if in_warnings else program.errors_had;
    for alert in alerts {
        if alert.code is not None and alert.code.code == code {
            return True;
        }
    }
    return False;
}

# ──────────────────────────────────────────────────────────────────
# Item 1 -- for-loop auto-fragment + key derivation (3 priorities still failing)
# ──────────────────────────────────────────────────────────────────
test "rec 1.1: for-loop auto-fragment lifts an explicit key= from one child" {
    # Issue #6082 item 1, priority 1: when one child in a for-loop slot
    # carries an explicit `key=`, ViewLowerPass should LIFT that key to
    # the synthesized `<React.Fragment>` wrapper and STRIP it from the
    # child. The iteration is then one keyed unit; the lifted key
    # expression is what the React diff uses for identity.
    es_ast = compile_to_esast("loop_auto_fragment_lifted_key.cl.jac");
    js_code = es_to_js(es_ast);

    assert "__jacJsx(Fragment," in js_code or "React.Fragment" in js_code , (
        "iteration must be wrapped in a synthesized Fragment:\n" + js_code
    );
    # The Fragment must carry the lifted key.
    import re;
    frag_match = re.search(r'__jacJsx\(Fragment,\s*\{[^}]*"key":\s*([^,}]+)', js_code);
    assert frag_match is not None , (
        "the Fragment wrapper must carry the lifted key:\n" + js_code
    );
    # The Card child must no longer carry `key=` after the lift.
    card_match = re.search(r'__jacJsx\(Card,\s*(\{[^}]*\})', js_code);
    assert card_match is not None , "the Card call must be present";
    assert '"key"' not in card_match.group(1) , (
        "the explicit key= on the child must be stripped after being "
        "lifted to the Fragment, but it survived in:\n" + card_match.group(1)
    );
}

test "rec 1.2: for-loop auto-fragment derives key from jid(loop_var) for typed obj" {
    # Issue #6082 item 1, priority 2: when the loop var is typed as a
    # Jac obj or node, the synthesized Fragment's key is derived from
    # `jid(loop_var)` -- the canonical Jac object identity.
    es_ast = compile_to_esast("loop_auto_fragment.cl.jac");
    js_code = es_to_js(es_ast);

    assert "__jacJsx(Fragment," in js_code or "React.Fragment" in js_code , (
        "iteration must be wrapped in a synthesized Fragment:\n" + js_code
    );
    assert '"key":' in js_code , ("the Fragment must carry a key prop:\n" + js_code);
    assert "_jac.builtin.jid(tweet)" in js_code , (
        "key should be derived from jid(loop_var) when the loop var is "
        "a typed obj:\n" + js_code
    );
}

test "rec 1.3: for-loop auto-fragment uses the counter for IterForStmt" {
    # Issue #6082 item 1, priority 3: when the loop is a counted form
    # (`for i = 0 to i < N by i += 1`), the synthesized Fragment's key
    # is the loop counter -- no jid() lookup needed and no lifted key.
    es_ast = compile_to_esast("loop_auto_fragment_counter.cl.jac");
    js_code = es_to_js(es_ast);

    assert "__jacJsx(Fragment," in js_code or "React.Fragment" in js_code , (
        "iteration must be wrapped in a synthesized Fragment:\n" + js_code
    );
    import re;
    assert re.search(r'__jacJsx\(Fragment,\s*\{[^}]*"key":\s*i\b', js_code) , (
        "the Fragment's key should be the counter variable `i`:\n" + js_code
    );
    # The counted IterForStmt should lower to a JS counted for-loop
    # (init / condition / update form), not a `for ... of`.
    assert re.search(r"for\s*\(\s*(let|var)\s+i\s*=\s*0", js_code) , (
        "a counted IterForStmt should lower to a JS counted for-loop:\n" + js_code
    );
}

# ──────────────────────────────────────────────────────────────────
# Items 3 / 5 / 7 -- view-lowering extensions
# ──────────────────────────────────────────────────────────────────
test "rec 2: try/awaiting with except synthesises a JacClientErrorBoundary wrapper" {
    # On the cl target, when a slot `try` carries both `awaiting` and at
    # least one `except` clause, ViewLowerPass should synthesize a
    # `<JacClientErrorBoundary fallback={...}>` around the existing
    # `<JacAwaiting fallback={...}>{...}</JacAwaiting>` wrapper. The
    # except-arm bodies feed the error-boundary's fallback the same way
    # the awaiting body feeds the suspense fallback.
    es_ast = compile_to_esast("try_awaiting_except.cl.jac");
    js_code = es_to_js(es_ast);

    assert "JacClientErrorBoundary" in js_code , (
        "an except-arm alongside awaiting should synthesize a "
        "<JacClientErrorBoundary> wrapper:\n" + js_code
    );
    import re;
    assert re.search(
        r'import\s*\{[^}]*\bJacClientErrorBoundary\b[^}]*\}\s*' + r'from\s*[\'"]@jac/runtime[\'"]',
        js_code
    ) , ("JacClientErrorBoundary should be auto-imported from @jac/runtime");
    # Both the awaiting body and the except body content survive.
    assert "Loading" in js_code;
    assert "Something went wrong" in js_code;
}

test "rec 4: static JSX subtree closing only over module-level bindings is hoisted" {
    # JSX subtrees whose only free variables are module-level bindings
    # (no has, no params, no slot locals) are hoisted to a module-level
    # `const` and referenced from the render site. Solid-style auto-
    # optimization driven by a pass-internal analysis.
    #
    # POST-IMPLEMENTATION TIGHTENING: this test locks in `__jac_static_<N>`
    # as the const-naming convention, but issue #6082 only specifies "a
    # module-level `const`". If the implementer picks a different name
    # (`__jac_view_const_<N>`, `__hoisted_<N>`, ...), loosen the regex to
    # match whatever scheme they choose rather than rejecting a correct
    # implementation.
    es_ast = compile_to_esast("static_hoist.cl.jac");
    js_code = es_to_js(es_ast);

    # A module-level hoist binding should exist, by convention prefixed
    # `__jac_static_` to match the ambient-builtin naming style.
    import re;
    assert re.search(r"(const|let)\s+__jac_static_\w+\s*=\s*__jacJsx\(", js_code) , (
        "a static JSX subtree should be hoisted to a module-level const "
        "named __jac_static_<N>:\n" + js_code
    );
    # The render site must reference the hoisted const rather than
    # inlining the subtree.
    assert js_code.count("__jac_static_") >= 2 , (
        "the hoisted const should be both defined and referenced:\n" + js_code
    );
}

test "rec 6: def -> JsxElement body with statement-level JSX (no return) lowers to slot IIFE" {
    # In client context, when a `def -> JsxElement` body contains
    # top-level JSX ExprStmts without an explicit `return <jsx>;`, apply
    # the accumulator-IIFE lowering to the function body itself.
    es_ast = compile_to_esast("stmt_body_view.cl.jac");
    js_code = es_to_js(es_ast);

    # The function-body-as-outer-slot lowering reuses the slot
    # accumulator convention.
    assert "__jac_view_kids" in js_code , (
        "function-body-position JSX statements should use the same "
        "accumulator pattern as slot bodies:\n" + js_code
    );
    # Both branches' content survives.
    assert "Hello, admin" in js_code;
    assert "Hello, " in js_code;
    # The component returns the accumulated fragment, not undefined.
    import re;
    assert re.search(r"return\s+__jacJsx\(", js_code) , (
        "the implicit outer-slot lowering must return the accumulated "
        "JSX fragment:\n" + js_code
    );
}

test "rec 7: Ref[T] field declared with has lowers to useRef(null) in client context" {
    # Ambient `Ref[T]` type -- `has buttonRef: Ref[HTMLButtonElement];`
    # in client context lowers to `useRef(null)`, mirroring how `has x:
    # int = 0;` lowers to `useState(0)`.
    es_ast = compile_to_esast("has_ref.cl.jac");
    js_code = es_to_js(es_ast);

    assert "useRef(null)" in js_code , (
        "`has buttonRef: Ref[...]` should lower to useRef(null):\n" + js_code
    );
    # `useRef` must be imported from react like `useState` is for has-state.
    import re;
    assert re.search(
        r'import\s*\{[^}]*\buseRef\b[^}]*\}\s*from\s*[\'"]react[\'"]', js_code
    ) , (
        "useRef should be auto-imported from react when a Ref-typed "
        "has-field is present:\n" + js_code
    );
}

test "rec 8: try/awaiting on sv target streams the awaiting body (no W2020 drop)" {
    # Today the sv target emits W2020 and drops the awaiting body. Once
    # the streaming-SSR lowering lands, W2020 should not fire and the
    # awaiting body should appear in the sv-target output so progressive
    # rendering can fall back to it before the try body resolves.
    #
    # POST-IMPLEMENTATION TIGHTENING: this test only asserts that W2020
    # stops firing -- necessary but not sufficient. A sham implementation
    # that just suppresses the warning without lowering the awaiting body
    # would pass. Once the SSR design lands, add an assertion that the
    # awaiting body's HTML actually appears in the SSR output before the
    # try body's resolved content (e.g., as a Suspense boundary marker
    # in the streamed chunks).
    prog = compile_for_diag("try_awaiting_sv.sv.jac");
    assert not has_code(prog, "W2020", in_warnings=True) , (
        "once sv awaiting lowering lands, W2020 should no longer fire; "
        "warnings were: " + str(
            [
                (w.code.code if w.code else "?") + ": " + str(w)
                for w in prog.warnings_had
            ]
        )
    );
}

test "rec 9: a .style.css annex is auto-scoped and rewrites JSX className refs" {
    # Files sharing a base name form one logical module. A `.style.css`
    # annex declares scoped classes for the module's components -- the
    # compiler hashes selectors and rewrites JSX `className` literals
    # that match a declared class.
    es_ast = compile_to_esast("style_annex.cl.jac");
    js_code = es_to_js(es_ast);

    # The bare class name `card` in the source must be rewritten to a
    # hashed form like `card-<8 hex>`.
    import re;
    assert re.search(r'"className":\s*"card-[0-9a-f]{8}"', js_code) , (
        "class names declared in the .style.css annex should be hashed "
        "and the JSX className literal rewritten:\n" + js_code
    );
    # A bare-name reference would mean no rewrite happened.
    assert '"className": "card"' not in js_code , (
        "the unrewritten bare class name must not survive in the bundle"
    );
}

test "rec 10: walker report inside a try/awaiting body streams progressive frames" {
    # The PR-#6063 scoped-out item: when a slot's try body spawns a
    # walker, each `report` issued during the dispatched-but-not-joined
    # window streams a fresh frame into the slot's awaiting body. The
    # cl-target lowering should auto-import a runtime hook and wire the
    # walker's report stream to the awaiting fallback so successive
    # reports replace the visible frame.
    #
    # POST-IMPLEMENTATION TIGHTENING: this test only validates the
    # import and reference of `JacProgressiveAwaiting`. A sham
    # implementation that just renames the wrapper without wiring the
    # walker's report stream would pass. Once the report-channel design
    # is settled (e.g., `useSyncExternalStore` subscription, a custom
    # hook taking the spawn handle, a generator-based primitive), add an
    # assertion that the actual stream-consumption path is present at
    # the call site -- not just the wrapper identifier.
    es_ast = compile_to_esast("walker_progressive.cl.jac");
    js_code = es_to_js(es_ast);

    # The progressive-frames runtime hook needs to be referenced from
    # the lowered bundle. Convention follows the JacAwaiting auto-import
    # pattern.
    assert "JacProgressiveAwaiting" in js_code , (
        "a try/awaiting body containing a walker spawn should lower to "
        "a runtime wrapper that consumes the walker's report stream:\n" + js_code
    );
    import re;
    assert re.search(
        r'import\s*\{[^}]*\bJacProgressiveAwaiting\b[^}]*\}\s*' + r'from\s*[\'"]@jac/runtime[\'"]',
        js_code
    ) , ("JacProgressiveAwaiting should be auto-imported from @jac/runtime");
}
