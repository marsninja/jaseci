"""Optimistic-concurrency tests for the SQLite backend (#6266 parity).

The version-CAS that stops concurrent check-then-create from minting
duplicate child nodes is implemented in core SqliteMemory (`_merge_write` +
`apply`), so the local/no-jac-scale pathway gets the same protection as the
Mongo backend. Two SqliteMemory instances on one db file model two workers
sharing a SQLite database; no Docker/testcontainers needed.

Anchor handles are typed `any`: the checker has no stub for `.__jac__` /
anchor metadata, and these tests poke the persistence layer directly.
"""

import os;
import from tempfile { mkdtemp }

import from jaclang.jac0core.archetype { GenericEdge, Root }
import from jaclang.runtimelib.changeset { ChangeSet }
import from jaclang.runtimelib.exceptions { WriteConflict }
import from jaclang.runtimelib.memory { SqliteMemory }


"""A fresh persistent edge anchor (only its id matters for these tests)."""
def _edge -> any {
    edge_arch: any = GenericEdge();
    e: any = edge_arch.__jac__;
    e.persistent = True;
    return e;
}


"""Seed a fresh Root at version 0 in `db`; return its id."""
def _seed_root(db: str) -> any {
    backend: any = SqliteMemory(path=db);
    root_arch: any = Root();
    r0: any = root_arch.__jac__;
    r0.persistent = True;
    r0.root = r0.id;
    cs0: any = ChangeSet();
    cs0.record_create(r0);
    backend.apply(cs0);
    return r0.id;
}


"""One worker's find-or-create with replay on conflict; 'created' or 'found'."""
def _find_or_create(db: str, rid: any) -> str {
    be: any = SqliteMemory(path=db);
    attempt = 0;
    while attempt < 5 {
        attempt += 1;
        r: any = be.get(rid);
        if len(r.edges) > 0 {
            return "found";
        }
        e: any = _edge();
        r.edges.append(e);
        cs: any = ChangeSet();
        cs.record_edge_delta(r, [e.id], []);
        rep: any = be.apply(cs);
        if rep.conflicts {
            continue;
        }
        return "created";
    }
    return "exhausted";
}


test "OCC (SQLite): version-CAS detects a concurrent root mutation" {
    db = os.path.join(mkdtemp(), "g.db");
    rid = _seed_root(db);

    # Two workers load the root at the same version (separate connections).
    b1: any = SqliteMemory(path=db);
    b2: any = SqliteMemory(path=db);
    h1: any = b1.get(rid);
    h2: any = b2.get(rid);
    assert h1.version == 0 and h2.version == 0;

    # Worker 1 wins and bumps the version.
    e1: any = _edge();
    h1.edges.append(e1);
    cs1: any = ChangeSet();
    cs1.record_edge_delta(h1, [e1.id], []);
    r1: any = b1.apply(cs1);
    assert not r1.conflicts and not r1.failed;
    assert h1.version == 1;

    # Worker 2 is still at v0 -> CAS miss -> recorded WriteConflict.
    e2: any = _edge();
    h2.edges.append(e2);
    cs2: any = ChangeSet();
    cs2.record_edge_delta(h2, [e2.id], []);
    r2: any = b2.apply(cs2);
    assert len(r2.conflicts) == 1 , f"expected 1 conflict, got {r2.conflicts}";
    wc: any = r2.conflicts[0];
    assert wc.expected_version == 0 and wc.actual_version == 1;
}


test "OCC (SQLite) + replay converges concurrent find-or-create to one child" {
    db = os.path.join(mkdtemp(), "g.db");
    rid = _seed_root(db);

    # Both workers read the empty root before either commits (the #6266 A/B
    # interleaving).
    bA: any = SqliteMemory(path=db);
    bB: any = SqliteMemory(path=db);
    rA: any = bA.get(rid);
    rB: any = bB.get(rid);
    assert len(rA.edges) == 0 and len(rB.edges) == 0;

    # A wins.
    eA: any = _edge();
    rA.edges.append(eA);
    csA: any = ChangeSet();
    csA.record_edge_delta(rA, [eA.id], []);
    repA: any = bA.apply(csA);
    assert not repA.conflicts;

    # B's stale commit conflicts...
    eB: any = _edge();
    rB.edges.append(eB);
    csB: any = ChangeSet();
    csB.record_edge_delta(rB, [eB.id], []);
    repB: any = bB.apply(csB);
    assert len(repB.conflicts) == 1;

    # ...so B replays, re-reads, and converges on the find branch.
    outB = _find_or_create(db, rid);
    assert outB == "found" , f"replay should converge to found, got {outB}";

    # The fix: exactly one child linked onto the root (the bug produced two).
    final: any = SqliteMemory(path=db).get(rid);
    assert len(final.edges) == 1 , f"expected 1 linked child, got {len(final.edges)}";
}
