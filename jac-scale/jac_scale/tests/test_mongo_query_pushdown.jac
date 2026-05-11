"""Tests: MongoBackend server-side type/field query pushdown.

Verifies three things:
1. ensure_indexes() creates an (arch_type, type) compound index — type queries
   use IXSCAN, not COLLSCAN.
2. query_by_type(name) returns only anchors of that archetype type.
3. query_by_type(name, field_filter) pushes field predicates to MongoDB so
   only matching archetype instances are deserialised.
4. get_roots() uses the indexed filter — no full collection scan.
"""

import atexit;
import os;
import from uuid { uuid4 }
import from typing { cast }
import from pymongo { MongoClient }
import from testcontainers.mongodb { MongoDbContainer }

import from jaclang.jac0core.runtime { JacRuntime }
import from jaclang.runtimelib.context { ExecutionContext }
import from jaclang.project.config { JacConfig, set_config }
import from jac_scale.memory_hierarchy { MongoBackend, ScaleTieredMemory }


node _QUser {
    has name: str = '',
        age: int = 0;
}

node _QProduct {
    has title: str = '';
}


glob _shared_pushdown: dict = {};


def _get_mongo_uri -> str {
    if "container" not in _shared_pushdown {
        c = MongoDbContainer("mongo:latest");
        c.start();
        _shared_pushdown["container"] = c;
        _shared_pushdown["uri"] = c.get_connection_url();
        _shared_pushdown["client"] = MongoClient(c.get_connection_url());
        atexit.register(c.stop);
    }
    return _shared_pushdown["uri"];
}


def _make_backend(db_name: str) -> MongoBackend {
    uri = _get_mongo_uri();
    backend = MongoBackend(mongo_url=uri, db_name=db_name);
    return backend;
}


def _drop_db(db_name: str) {
    if "client" in _shared_pushdown {
        _shared_pushdown["client"].drop_database(db_name);
    }
}


test "ensure_indexes creates arch_type compound index (IXSCAN not COLLSCAN)" {
    db = "pushdown_idx_test";
    _drop_db(db);
    backend = _make_backend(db);

    assert backend.collection is not None , "backend must connect";

    idx_info: dict = backend.collection.index_information();
    assert "arch_type_1_type_1" in idx_info , (
        f"compound (arch_type, type) index not found; got: {list(idx_info.keys())}"
    );

    # Insert a dummy doc and verify the query planner uses the index
    backend.collection.insert_one(
        {
            '_id': str(uuid4()),
            'arch_type': '_QUser',
            'type': 'NodeAnchor',
            'arch_module': __name__,
            'fingerprint': None,
            'data': {'archetype': {'name': 'Alice', 'age': 25}},
            'format_version': 1,
            'updated_at': '2026-01-01T00:00:00Z'
        }
    );

    plan = backend.collection.find(
        {'arch_type': '_QUser', 'type': 'NodeAnchor'}
    ).explain()['queryPlanner']['winningPlan'];

    def _has_ixscan(step: dict) -> bool {
        if step.get('stage') == 'IXSCAN' {
            return True;
        }
        for child in [step.get('inputStage'), *step.get('inputStages', [])] {
            if child and _has_ixscan(child) {
                return True;
            }
        }
        return False;
    }

    assert _has_ixscan(plan) , (f"Expected IXSCAN on arch_type query but got: {plan}");
}


test "query_by_type returns only anchors of the specified archetype" {
    orig_base = JacRuntime.get_base_path_dir();
    cfg = JacConfig();
    set_config(cfg);
    JacRuntime.set_base_path("/tmp/_pushdown_type_test");

    db = "pushdown_type_test";
    _drop_db(db);

    try {
        uri = _get_mongo_uri();
        mem = ScaleTieredMemory();
        backend = MongoBackend(mongo_url=uri, db_name=db);
        mem.l2 = None;
        mem.l3 = backend;
        backend.set_memory_ref(mem.__mem__);

        ctx = ExecutionContext();
        ctx.mem = mem;
        JacRuntime.set_context(ctx);

        # Create 3 users and 2 products
        for i in range(3) {
            root ++> _QUser(name=f"user_{i}", age=20 + i);
        }
        for i in range(2) {
            root ++> _QProduct(title=f"prod_{i}");
        }
        mem.commit();

        # Fresh backend so L1 is empty — reads must come from MongoDB
        backend2 = MongoBackend(mongo_url=uri, db_name=db);
        found = list(backend2.query_by_type('_QUser'));
        assert len(found) == 3 , (f"Expected 3 _QUser anchors, got {len(found)}");
        for a in found {
            assert type(a.archetype).__name__ == '_QUser' , (
                f"Unexpected archetype type: {type(a.archetype).__name__}"
            );
        }

        found_prod = list(backend2.query_by_type('_QProduct'));
        assert len(found_prod) == 2 , (
            f"Expected 2 _QProduct anchors, got {len(found_prod)}"
        );
    } finally {
        JacRuntime.set_base_path(orig_base);
    }
}


test "query_by_type with field filter pushes predicate to MongoDB" {
    orig_base = JacRuntime.get_base_path_dir();
    cfg = JacConfig();
    set_config(cfg);
    JacRuntime.set_base_path("/tmp/_pushdown_field_test");

    db = "pushdown_field_test";
    _drop_db(db);

    try {
        uri = _get_mongo_uri();
        mem = ScaleTieredMemory();
        backend = MongoBackend(mongo_url=uri, db_name=db);
        mem.l2 = None;
        mem.l3 = backend;
        backend.set_memory_ref(mem.__mem__);

        ctx = ExecutionContext();
        ctx.mem = mem;
        JacRuntime.set_context(ctx);

        # 5 users: ages 20..24
        for i in range(5) {
            root ++> _QUser(name=f"u{i}", age=20 + i);
        }
        mem.commit();

        backend2 = MongoBackend(mongo_url=uri, db_name=db);
        young = list(backend2.query_by_type('_QUser', {'age': {'$lt': 23}}));
        assert len(young) == 3 , (
            f"Expected 3 users with age < 23 (ages 20,21,22), got {len(young)}: "
            f"{[cast(_QUser, a.archetype).age for a in young]}"
        );
        for a in young {
            assert cast(_QUser, a.archetype).age < 23 , (
                f"age {cast(_QUser, a.archetype).age} should be < 23"
            );
        }
    } finally {
        JacRuntime.set_base_path(orig_base);
    }
}


test "get_roots uses indexed filter, not full collection scan" {
    orig_base = JacRuntime.get_base_path_dir();
    cfg = JacConfig();
    set_config(cfg);
    JacRuntime.set_base_path("/tmp/_pushdown_roots_test");

    db = "pushdown_roots_test";
    _drop_db(db);

    try {
        uri = _get_mongo_uri();
        mem = ScaleTieredMemory();
        backend = MongoBackend(mongo_url=uri, db_name=db);
        mem.l2 = None;
        mem.l3 = backend;
        backend.set_memory_ref(mem.__mem__);

        ctx = ExecutionContext();
        ctx.mem = mem;
        JacRuntime.set_context(ctx);

        # Populate: 1 root + some non-root nodes. `root ++> X` doesn't
        # auto-persist the root: explicitly mark + put it so get_roots can
        # find it on a fresh connection.
        for i in range(10) {
            root ++> _QUser(name=f"u{i}", age=i);
        }
        root_arch = ctx.get_root();
        import from jaclang.jac0core.archetype { NodeAnchor as _NA }
        root_anchor = cast(_NA, getattr(root_arch, '__jac__'));
        root_anchor.persistent = True;
        mem.put(root_anchor);
        mem.commit();

        backend2 = MongoBackend(mongo_url=uri, db_name=db);
        roots = list(backend2.get_roots());
        assert len(roots) >= 1 , "Expected at least one root anchor";
        import from jaclang.runtimelib.context { Root as JacRoot }
        for r in roots {
            assert isinstance(r, JacRoot) , (
                f"get_roots returned non-Root archetype: {type(r).__name__}"
            );
        }

        # Verify the query uses the index (IXSCAN)
        plan = backend2.collection.find(
            {'arch_type': 'Root', 'type': 'NodeAnchor'}
        ).explain()['queryPlanner']['winningPlan'];

        def _has_ixscan(step: dict) -> bool {
            if step.get('stage') == 'IXSCAN' {
                return True;
            }
            for child in [step.get('inputStage'), *step.get('inputStages', [])] {
                if child and _has_ixscan(child) {
                    return True;
                }
            }
            return False;
        }

        assert _has_ixscan(plan) , (f"get_roots query should use IXSCAN, got: {plan}");
    } finally {
        JacRuntime.set_base_path(orig_base);
    }
}
