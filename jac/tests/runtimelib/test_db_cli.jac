"""End-to-end tests for the `jac db` CLI subcommands.

Each test spawns real `jac db ...` (and sometimes `jac enter`) subprocesses
so we exercise the full subprocess + DB-on-disk + CLI argparse path —
exactly the interface a developer or operator uses.
"""

import os;
import subprocess;
import sys;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }


"""Run a subprocess and return (rc, stdout, stderr)."""
def _run(cwd: str, argv: list) -> tuple {
    result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=180);
    return (result.returncode, result.stdout, result.stderr);
}


def _jac(cwd: str, args: list) -> tuple {
    return _run(cwd, [sys.executable, "-m", "jaclang"] + args);
}


glob V1_LEGACY = "node LegacyPerson { has name: str; }\n"
     "walker create {\n"
     "    can s with Root entry {\n"
     "        here ++> LegacyPerson(name=\"alice\");\n"
     "        here ++> LegacyPerson(name=\"bob\");\n"
     "    }\n"
     "}\n",
     V2_PERSON = "node Person { has name: str; }\n"
     "walker dump {\n"
     "    can r with Root entry { visit [-->]; }\n"
     "    can p with Person entry { print(here.name); }\n"
     "}\n";


test "db inspect prints a summary with counts" {
    with TemporaryDirectory() as raw_tmpdir {
        tmpdir = str(raw_tmpdir);
        app = Path(tmpdir) / "app.jac";
        app.write_text(V1_LEGACY);
        (rc, _, err) = _jac(tmpdir, ["enter", str(app), "create"]);
        assert rc == 0 , f"create failed: {err}";
        (rc, out, err) = _jac(tmpdir, ["db", "inspect"]);
        assert rc == 0 , f"inspect failed: {err}";
        # Summary line + per-arch_type table. Rich truncates the table's
        # arch_type column at narrow terminal widths (notably in CI), so
        # assert on a class-name prefix that survives truncation rather
        # than the full literal "LegacyPerson".
        assert "format_version=1" in out;
        assert "anchors=" in out;
        assert "Legac" in out;
        assert "Root" in out;
    }
}


test "db alias add/list/remove round-trip works" {
    with TemporaryDirectory() as raw_tmpdir {
        tmpdir = str(raw_tmpdir);
        app = Path(tmpdir) / "app.jac";
        app.write_text(V1_LEGACY);
        # Need a DB to act on.
        _jac(tmpdir, ["enter", str(app), "create"]);
        # Initially empty.
        (rc, out, _) = _jac(tmpdir, ["db", "alias", "list"]);
        assert rc == 0;
        assert "No DB-resident aliases" in out;
        # Add.
        (rc, out, _) = _jac(tmpdir, ["db", "alias", "add", "old.mod.X", "new.mod.Y"]);
        assert rc == 0;
        assert "registered" in out.lower();
        # List shows it.
        (rc, out, _) = _jac(tmpdir, ["db", "alias", "list"]);
        assert rc == 0;
        assert "old.mod.X" in out and "new.mod.Y" in out;
        # Remove.
        (rc, out, _) = _jac(tmpdir, ["db", "alias", "remove", "old.mod.X"]);
        assert rc == 0;
        assert "Removed" in out;
        (rc, out, _) = _jac(tmpdir, ["db", "alias", "list"]);
        assert rc == 0;
        assert "No DB-resident aliases" in out;
    }
}


test "db recover-all rescues quarantined rows after CLI alias add" {
    with TemporaryDirectory() as raw_tmpdir {
        tmpdir = str(raw_tmpdir);
        app = Path(tmpdir) / "app.jac";
        # v1: LegacyPerson is the live class.
        app.write_text(V1_LEGACY);
        _jac(tmpdir, ["enter", str(app), "create"]);
        # Swap to v2: Person, with NO @archetype_alias. Old anchors quarantine
        # when the v2 walker tries to traverse them.
        app.write_text(V2_PERSON);
        _jac(tmpdir, ["enter", str(app), "dump"]);
        # Confirm quarantine populated.
        (rc, out, _) = _jac(tmpdir, ["db", "inspect"]);
        assert rc == 0;
        assert "quarantined=2" in out;
        # Operator-side rescue: register the alias in the DB, then recover.
        (rc, _, _) = _jac(
            tmpdir, ["db", "alias", "add", "__main__.LegacyPerson", "__main__.Person"]
        );
        assert rc == 0;
        (rc, out, err) = _jac(tmpdir, ["db", "recover-all", "--app", str(app)]);
        assert rc == 0 , f"recover-all failed: {err}";
        assert "Recovered 2 of 2" in out;
        # Inspect confirms quarantine cleared and rows now stamped as Person.
        (rc, out, _) = _jac(tmpdir, ["db", "inspect"]);
        assert rc == 0;
        assert "quarantined=0" in out;
        assert "Person" in out;
        # Final smoke: the dump walker now finds the recovered data.
        (rc, out, err) = _jac(tmpdir, ["enter", str(app), "dump"]);
        assert rc == 0 , f"dump failed: {err}";
        assert "alice" in out and "bob" in out;
    }
}


test "db quarantine list and show return data, never silently empty" {
    with TemporaryDirectory() as raw_tmpdir {
        tmpdir = str(raw_tmpdir);
        app = Path(tmpdir) / "app.jac";
        app.write_text(V1_LEGACY);
        _jac(tmpdir, ["enter", str(app), "create"]);
        # Force quarantine.
        app.write_text(V2_PERSON);
        _jac(tmpdir, ["enter", str(app), "dump"]);
        # quarantine list shows the row(s). Rich truncates long arch_type
        # cells (e.g. "__main__.LegacyPerson" -> "__main__.Legac…"), so we
        # assert on the table title and a class-name prefix that survives
        # truncation rather than the full literal.
        (rc, out, _) = _jac(tmpdir, ["db", "quarantine", "list"]);
        assert rc == 0;
        assert "Quarantined" in out;
        assert "Legac" in out;
        # Find a row id from the listing (truncated form like "abc12345…" is
        # fine — we'll grep an id straight from the DB instead).
        import sqlite3;
        data_dir = Path(tmpdir) / ".jac" / "data";
        dbs = sorted(data_dir.glob("*.db"));
        assert dbs;
        conn = sqlite3.connect(str(dbs[0]));
        ids = [r[0] for r in conn.execute("SELECT id FROM anchors_quarantine LIMIT 1")];
        conn.close();
        assert ids;
        (rc, out, _) = _jac(tmpdir, ["db", "quarantine", "show", ids[0]]);
        assert rc == 0;
        assert ids[0] in out;
        assert "LegacyPerson" in out;
    }
}


test "db rejects bad sub-actions with helpful errors" {
    with TemporaryDirectory() as raw_tmpdir {
        tmpdir = str(raw_tmpdir);
        app = Path(tmpdir) / "app.jac";
        app.write_text(V1_LEGACY);
        _jac(tmpdir, ["enter", str(app), "create"]);
        (rc, _, err) = _jac(tmpdir, ["db", "alias", "frobnicate"]);
        assert rc != 0;
        assert "alias" in err.lower() or "expected" in err.lower();
        (rc, _, err) = _jac(tmpdir, ["db", "quarantine", "frobnicate"]);
        assert rc != 0;
    }
}
