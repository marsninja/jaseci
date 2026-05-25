# ruff: noqa: T201  (this is a CLI tool; console output via print is intended)
"""Codebase-wide @property -> native-property refactor driver (W3043).

The single-file `jac lint --fix` path parses annex (.impl.jac) files parse-only,
so an `impl Cls.prop` body cannot see that `prop` is a @property (no decl_link).
This driver closes that gap in two phases:

  1. Scan every decl .jac file for `@property`/`@x.setter`/`@x.deleter` abilities
     and record their dotted impl target ("Cls.prop", "Outer.Inner.prop") -> role.
  2. Publish that map into JacAutoLintPass.PROPERTY_IMPL_TARGETS, then run the
     normal lint+format fix on each file. The decl side converts from the
     decorator; the impl side consults the published map.

Usage:
    python scripts/property_to_native.py <file_or_dir> [<file_or_dir> ...]
    python scripts/property_to_native.py --dry-run <paths...>
"""

from __future__ import annotations

import sys
from pathlib import Path

import jaclang.compiler.passes.tool.jac_auto_lint_pass as lintmod
import jaclang.jac0core.unitree as uni
from jaclang.jac0core.program import JacProgram

# NOTE: the driver runs the *full* autolint rule set, not a W3043-only subset.
# Restricting to W3043 via `[check.lint] select` exposes a latent bug: several
# rules (e.g. combine-has) mutate nodes in place during their check and only
# "apply" the result when their warning is *not* suppressed; suppressing them
# leaves the in-place mutation orphaned and corrupts the tree. Target files are
# expected to already be lint-clean, so every non-W3043 rule is a no-op and the
# resulting diff is property-only.


def _decorator_role(ab: uni.Ability) -> str:
    """Mirror of JacAutoLintPass._property_role_of_ability for the scan phase."""
    if not ab.decorators:
        return ""
    for dec in ab.decorators:
        if isinstance(dec, uni.Name) and dec.value == "property":
            return "property"
        if (
            isinstance(dec, uni.AtomTrailer)
            and dec.is_attr
            and isinstance(dec.right, uni.Name)
        ):
            if dec.right.value == "setter":
                return "setter"
            if dec.right.value == "deleter":
                return "deleter"
    return ""


def _walk_props(node: uni.UniNode, chain: list[str], out: dict[str, str]) -> None:
    """Recurse archetypes, recording dotted target -> role for property abilities."""
    body = getattr(node, "body", None)
    if not isinstance(body, list):
        return
    for item in body:
        if isinstance(item, uni.Archetype) and isinstance(item.name, uni.Name):
            _walk_props(item, chain + [item.name.value], out)
        elif isinstance(item, uni.Ability) and isinstance(item.name_ref, uni.Name):
            role = _decorator_role(item)
            if role and chain:
                dotted = ".".join(chain + [item.name_ref.value])
                # A getter wins over a later-seen setter/deleter for the same
                # name: `impl Cls.prop` resolves to the getter.
                if out.get(dotted) != "property":
                    out[dotted] = role


def scan_property_targets(files: list[Path]) -> dict[str, str]:
    out: dict[str, str] = {}
    for f in files:
        prog = JacProgram()
        try:
            mod = prog.parse_str(f.read_text(encoding="utf-8"), str(f))
        except Exception as e:  # noqa: BLE001
            print(f"  ! scan parse failed for {f}: {e}", file=sys.stderr)
            continue
        _walk_props(mod, [], out)
    return out


def collect_jac_files(paths: list[str]) -> list[Path]:
    files: list[Path] = []
    for p in paths:
        path = Path(p)
        if path.is_dir():
            files.extend(sorted(path.rglob("*.jac")))
        elif path.suffix == ".jac":
            files.append(path)
    # Skip annex files as primary targets; they are pulled in via their decl file.
    return [f for f in files if not f.name.endswith((".impl.jac", ".test.jac"))]


def _run_autolint(file_path: Path, dry_run: bool) -> list[Path]:
    """Convert @property on a decl file (and its annexes); write changes.

    Returns the list of files (decl + annexes) whose content changed.
    """
    prog = JacProgram.jac_file_formatter(str(file_path), auto_lint=True)
    changed: list[Path] = []
    try:
        formatted = prog.mod.main.gen.jac
        original = prog.mod.main.source.code
    except Exception:  # noqa: BLE001
        for err in prog.errors_had:
            print(f"  ! {err}", file=sys.stderr)
        return []
    if formatted != original:
        changed.append(file_path)
        if not dry_run:
            file_path.write_text(formatted, encoding="utf-8")
    for impl_mod in prog.mod.main.impl_mod:
        if impl_mod.gen.jac != impl_mod.source.code:
            ipath = Path(impl_mod.loc.mod_path)
            changed.append(ipath)
            if not dry_run:
                ipath.write_text(impl_mod.gen.jac, encoding="utf-8")
    return changed


def _normalize(path: Path) -> None:
    """Plain-format a single file in place to clean up synthetic-token spacing."""
    prog = JacProgram.jac_file_formatter(str(path), auto_lint=False)
    try:
        formatted = prog.mod.main.gen.jac
        original = prog.mod.main.source.code
    except Exception:  # noqa: BLE001
        return
    if formatted != original:
        path.write_text(formatted, encoding="utf-8")


def fix_file(file_path: Path, dry_run: bool) -> bool:
    """Convert @property on one decl file (and annexes), then normalize.

    The autolint pass rewrites impl targets in place with synthetic tokens whose
    source positions confuse the pretty-printer, so each changed file is then
    re-parsed and plain-formatted to normalize spacing/line breaks.
    """
    changed = _run_autolint(file_path, dry_run=dry_run)
    if not dry_run:
        for path in changed:
            _normalize(path)
    return bool(changed)


def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 2
    files = collect_jac_files(paths)
    print(f"Scanning {len(files)} decl files for @property targets...")
    targets = scan_property_targets(files)
    print(f"Found {len(targets)} property targets.")
    for k, v in sorted(targets.items()):
        print(f"  {k} -> {v}")
    # Publish the map for the impl-side rule (mutate in place to keep identity).
    lintmod.PROPERTY_IMPL_TARGETS.clear()
    lintmod.PROPERTY_IMPL_TARGETS.update(targets)
    # Only touch files that actually declare a @property; leave others untouched
    # so the refactor diff stays minimal.
    files = [f for f in files if "@property" in f.read_text(encoding="utf-8")]
    print(f"{len(files)} file(s) contain @property declarations.")
    changed_files = 0
    for f in files:
        if fix_file(f, dry_run):
            changed_files += 1
            print(f"  {'would change' if dry_run else 'changed'}: {f}")
    print(f"Done. {changed_files} file group(s) changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
