"""End-to-end tests for topology index using native Jac graph syntax.

Verifies correctness of the full pipeline: connect (+>) -> index update ->
query planning via edge ops (->) and filter comprehensions ([?:Type]) ->
correct results. Uses real Jac edge/filter syntax so regressions in the
compiler pipeline (exit_edge_ref_trailer, exit_filter_compr) are caught.
"""

import os;
import shutil;
import from tempfile { mkdtemp }
import from typing { Any }
import from jaclang { JacRuntimeInterface as Jac }
import from jaclang.jac0core.runtime { JacRuntime }
import from jaclang.runtimelib.context { ExecutionContext }
import from jaclang.project.config { JacConfig, set_config }

node TypeA {
    has val: int = 0;
}

node TypeB {
    has val: int = 0;
}

edge EdgeX {}
edge EdgeY {}

test "index type-filtered query returns correct results" {
    tmpdir = mkdtemp();
    orig_base = JacRuntime.base_path_dir;
    try {
        cfg = JacConfig();
        cfg.run.topology_index = True;
        set_config(cfg);
        JacRuntime.set_base_path(tmpdir);
        ctx = ExecutionContext();
        JacRuntime.set_context(ctx);

        r = root;
        Jac.save(r);

        for i in range(10) {
            r +>: EdgeX :+> TypeA(val=i);
        }
        for i in range(90) {
            r +>: EdgeX :+> TypeB(val=i);
        }
        Jac.save(r);

        # Type-filtered: only TypeA via EdgeX
        result = [r->:EdgeX:->[?:TypeA]];
        assert len(result) == 10 , f"Expected 10 TypeA, got {len(result)}";
        assert sorted([n.val for n in result]) == list(range(10));

        # Unfiltered: all 100 nodes
        result_all = [r->:EdgeX:->];
        assert len(result_all) == 100 , f"Expected 100 total, got {len(result_all)}";

        ctx.close();
    } finally {
        JacRuntime.set_base_path(orig_base);
        set_config(JacConfig());
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}

test "index results match non-indexed results in same context" {
    tmpdir = mkdtemp();
    orig_base = JacRuntime.base_path_dir;
    try {
        cfg = JacConfig();
        cfg.run.topology_index = True;
        set_config(cfg);
        JacRuntime.set_base_path(tmpdir);
        ctx = ExecutionContext();
        JacRuntime.set_context(ctx);

        r = root;
        Jac.save(r);
        for i in range(20) {
            r +>: EdgeX :+> TypeA(val=i);
        }
        for i in range(80) {
            r +>: EdgeX :+> TypeB(val=i);
        }
        Jac.save(r);

        # With index (default): type-filtered
        on_result = sorted([n.val for n in [r->:EdgeX:->[?:TypeA]]]);

        # Disable index and re-query in same context
        cfg.run.topology_index = False;
        set_config(cfg);
        off_result = sorted([n.val for n in [r->:EdgeX:->[?:TypeA]]]);

        assert off_result == on_result , f"Results differ: off={off_result} on={on_result}";
        assert len(off_result) == 20;

        ctx.close();
    } finally {
        JacRuntime.set_base_path(orig_base);
        set_config(JacConfig());
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}

test "index returns empty for non-matching edge type" {
    tmpdir = mkdtemp();
    orig_base = JacRuntime.base_path_dir;
    try {
        cfg = JacConfig();
        cfg.run.topology_index = True;
        set_config(cfg);
        JacRuntime.set_base_path(tmpdir);
        ctx = ExecutionContext();
        JacRuntime.set_context(ctx);

        r = root;
        Jac.save(r);
        for i in range(10) {
            r +>: EdgeX :+> TypeA(val=i);
        }
        Jac.save(r);

        # EdgeY not in graph — should be empty
        result = [r->:EdgeY:->[?:TypeA]];
        assert len(result) == 0 , f"Expected 0, got {len(result)}";

        ctx.close();
    } finally {
        JacRuntime.set_base_path(orig_base);
        set_config(JacConfig());
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}

test "post-hoc filter fused with edge-op produces same results" {
    tmpdir = mkdtemp();
    orig_base = JacRuntime.base_path_dir;
    try {
        cfg = JacConfig();
        cfg.run.topology_index = True;
        set_config(cfg);
        JacRuntime.set_base_path(tmpdir);
        ctx = ExecutionContext();
        JacRuntime.set_context(ctx);

        r = root;
        Jac.save(r);
        for i in range(10) {
            r +>: EdgeX :+> TypeA(val=i);
        }
        for i in range(90) {
            r +>: EdgeX :+> TypeB(val=i);
        }
        Jac.save(r);

        # Inline filter (already optimized)
        inline = sorted([n.val for n in [r->:EdgeX:->[?:TypeA]]]);

        # Post-hoc filter (should be fused and produce same results)
        posthoc = sorted([n.val for n in [r->:EdgeX:->][?:TypeA]]);

        assert inline == posthoc , f"Inline vs post-hoc differ: {inline} vs {posthoc}";
        assert len(inline) == 10;

        ctx.close();
    } finally {
        JacRuntime.set_base_path(orig_base);
        set_config(JacConfig());
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}

test "nested post-hoc filter as origin of outer edge-op" {
    tmpdir = mkdtemp();
    orig_base = JacRuntime.base_path_dir;
    try {
        cfg = JacConfig();
        cfg.run.topology_index = True;
        set_config(cfg);
        JacRuntime.set_base_path(tmpdir);
        ctx = ExecutionContext();
        JacRuntime.set_context(ctx);

        r = root;
        Jac.save(r);
        # root -> TypeA via EdgeX, TypeA -> TypeB via EdgeY
        for i in range(5) {
            a = TypeA(val=i);
            r +>: EdgeX :+> a;
            a +>: EdgeY :+> TypeB(val=i * 10);
        }
        # root -> TypeB via EdgeX (decoys)
        for i in range(20) {
            r +>: EdgeX :+> TypeB(val=100 + i);
        }
        Jac.save(r);

        # Inline multi-hop: get TypeB behind TypeA
        inline = sorted([n.val for n in [r->:EdgeX:->[?:TypeA]->:EdgeY:->[?:TypeB]]]);

        # Nested: post-hoc filter TypeA, then use as origin for EdgeY hop
        type_a_nodes = [r->:EdgeX:->][?:TypeA];
        nested = sorted([n.val for n in [type_a_nodes->:EdgeY:->[?:TypeB]]]);

        assert inline == nested , f"Inline vs nested differ: {inline} vs {nested}";
        assert inline == [0, 10, 20, 30, 40];

        ctx.close();
    } finally {
        JacRuntime.set_base_path(orig_base);
        set_config(JacConfig());
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}

test "plan_query bypasses index when no hop is filtered" {
    import from jaclang.jac0core.archetype {
        ObjectSpatialPath, ObjectSpatialDestination, EdgeDir
    }
    import from jaclang.runtimelib.topo_utils { plan_query }

    tmpdir = mkdtemp();
    orig_base = JacRuntime.base_path_dir;
    try {
        cfg = JacConfig();
        cfg.run.topology_index = True;
        set_config(cfg);
        JacRuntime.set_base_path(tmpdir);
        ctx = ExecutionContext();
        JacRuntime.set_context(ctx);

        r = root;
        Jac.save(r);
        for i in range(10) {
            r +>: EdgeX :+> TypeA(val=i);
        }
        Jac.save(r);

        # Fully unfiltered single-hop chain → planner must return None so
        # the runtime falls back to the natural edge-walk.
        unfiltered_path = ObjectSpatialPath(
            [r], [ObjectSpatialDestination(EdgeDir.OUT)]
        );
        assert plan_query(unfiltered_path) is None , (
            "plan_query should bypass TI for fully unfiltered chains"
        );

        # Edge-type filter alone is enough to engage the index.
        edge_filter = lambda e: Any : isinstance(e, EdgeX);
        edge_typed_path = ObjectSpatialPath(
            [r], [ObjectSpatialDestination(EdgeDir.OUT, edge_filter)]
        );
        assert plan_query(edge_typed_path) is not None , (
            "plan_query should engage TI when edge_type is filtered"
        );

        # Node-type filter alone also engages the index.
        node_filter = lambda n: Any : isinstance(n, TypeA);
        node_typed_path = ObjectSpatialPath(
            [r], [ObjectSpatialDestination(EdgeDir.OUT, None, node_filter)]
        );
        result = plan_query(node_typed_path);
        assert result is not None , "plan_query should engage TI when node_type is filtered";
        assert len(result) == 10 , f"expected 10 TypeA nodes, got {len(result)}";

        ctx.close();
    } finally {
        JacRuntime.set_base_path(orig_base);
        set_config(JacConfig());
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}

test "index built on root with null root field" {
    tmpdir = mkdtemp();
    orig_base = JacRuntime.base_path_dir;
    try {
        cfg = JacConfig();
        cfg.run.topology_index = True;
        set_config(cfg);
        JacRuntime.set_base_path(tmpdir);
        ctx = ExecutionContext();
        JacRuntime.set_context(ctx);

        r = root;
        Jac.save(r);
        r +>: EdgeX :+> TypeA(val=42);
        Jac.save(r);

        idx = r.__jac__.get_topology_index();
        assert len(idx) > 0 , "Index should have edges";
        assert len(idx.node_table) == 2 , "Index should have root + TypeA";

        ctx.close();
    } finally {
        JacRuntime.set_base_path(orig_base);
        set_config(JacConfig());
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}
