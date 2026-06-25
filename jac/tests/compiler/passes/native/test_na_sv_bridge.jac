"""End-to-end sv<->na bridge equivalence tests for the native standard library.

Each fixture is one mixed module: an `na {}` block and an `sv {}` block exercise
the SAME library through both backends, and `with entry` diffs the two outputs
and asserts they match. The fixtures run through the real `jac run` import/exec
path (the live na<->sv bridge), which is stricter than the AOT `prim_*`
equivalence harness in `jaclang/compiler/tests/` -- that one compiles each
backend separately and never exercises the bridge.

Each fixture runs in a SUBPROCESS: a native abort cannot be caught in-process,
so a regression would otherwise kill the test runner. We assert a clean exit and
the fixture's success marker.

Regression pinned here: a bridged `na {}` function that transitively read an
imported na module's `static has` class attribute used to ABORT, because
`meta_importer` injected the native engine and ran the module body without first
running the imported module's `__jac_glob_init` -- so the static field was an
uninitialized null. `meta_importer` now runs `init_native_globals` before exec().
The `datetime` case is the regression: its `na {}` block reads `timezone.utc`
(a `static has` on the bundled `datetime` module) and aborted (SIGABRT) before
the fix. `json` / `zlib` / `os` guard the bridge for modules that were already
working; `urllib` is a still-open, separate bug (see its skipped case).
"""
import os;
import subprocess;
import sys;
import from pathlib { Path }

glob FIXTURES = str(Path(__file__).resolve().parent / "fixtures");


"""Run `jac run <fixture>` in a subprocess; return (returncode, stdout, stderr)."""
def _jac_run(fixture: str, timeout: int = 300) -> tuple[int, str, str] {
    src = os.path.join(FIXTURES, fixture);
    assert os.path.exists(src) , f"fixture missing: {src}";
    proc = subprocess.run(
        [sys.executable, "-m", "jaclang", "run", src],
        capture_output=True,
        text=True,
        timeout=timeout
    );
    return (proc.returncode, proc.stdout, proc.stderr);
}


"""Assert the fixture exits cleanly (no native abort) and emits `marker`."""
def _assert_ok(fixture: str, marker: str) {
    (rc, out, err) = _jac_run(fixture);
    assert rc == 0 , (
        f"{fixture} exited {rc} (native bridge abort?)\n" + f"stdout tail: {out[-600:]}\nstderr tail: {err[-600:]}"
    );
    assert marker in out , (
        f"{fixture}: missing marker '{marker}' in output:\n{out[-600:]}"
    );
}


test "na<->sv equivalence: datetime -- imported static-field init (regression)" {
    # Regression for the `meta_importer` glob-init fix: the na block reads
    # `timezone.utc`, a `static has` on the bundled `datetime` module. Before the
    # fix that static field was an uninitialized null and the bridged call
    # aborted (SIGABRT); now both backends agree on all 14 civil-time checks.
    _assert_ok("na_sv_eq_datetime.jac", "datetime: 14/14");
}

test "na<->sv equivalence: json" {
    _assert_ok("na_sv_eq_json.jac", "json: 14/14");
}

test "na<->sv equivalence: zlib" {
    _assert_ok("na_sv_eq_zlib.jac", "zlib: 11/11");
}

test "na<->sv equivalence: os / os.path" {
    _assert_ok("na_sv_eq_os.jac", "os: 18/18");
}

test "na<->sv equivalence: urllib (KNOWN-OPEN: separate HTTPResponse/libcurl bridge bug)" {
    # Distinct from the static-field init fix above: `urlopen()` returns a
    # bundled `HTTPResponse` obj and drives libcurl through the FFI, and that
    # still SIGSEGVs across the live `jac run` na<->sv bridge even after globals
    # are initialized. The fixture is complete and self-validating; un-skip once
    # the obj/FFI marshalling across the JIT bridge is fixed.
    import pytest;
    pytest.skip(
        "urllib HTTPResponse + libcurl FFI across the live na<->sv bridge still " + "crashes; tracked separately from the static-field init fix"
    );
    _assert_ok("na_sv_eq_urllib.jac", "urllib: 3/3");
}
