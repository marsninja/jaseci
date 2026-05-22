"""Executable spec -- streaming awaiting frames (#6082 items 9 + 8-Tier3).

Expected to FAIL, and DESIGN-GATED -- these two items cannot turn green
until their upstream design lands:

  - rec 8:  item 9 -- sv-target (streaming SSR) lowering for `awaiting`.
            Today the sv target fires W2020 and drops the awaiting body.
            Gated on the streaming-SSR design (cross-ref #6055
            "Boundaries").
  - rec 10: item 8 Tier 3 -- walker `report` -> progressive `awaiting`
            frames. Gated on the `flow`/`wait` design in #6056.

Both tests carry POST-IMPLEMENTATION TIGHTENING notes: the assertions
are intentionally loose where the issue body leaves the contract open,
and must be sharpened once the implementer commits to a concrete shape.

Ordering note: walker_progressive embeds a `for` slot, so rec 10's
expected output depends on the for-loop auto-fragment lowering tracked
in the view-lowering spec (#6082 item 1) landing first.

Split out of #6088 so CI (`--exitfirst`) stays green on the
implementation branch while the spec remains a visible tracker.
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
