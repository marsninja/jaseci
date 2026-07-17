"""Tests for the bundled documentation corpus behind `jac guide`.

The corpus at jaclang/cli/docs is generated from docs/docs by
scripts/sync_agent_docs.py and served next to the curated skill guides:
namespaced names (ref/, learn/, tutorial/, internals/), unified resolution
through `get_guide`, and grep-style search via `grep_guides`. These tests
pin the corpus's presence in the package, the resolution rules (exact,
suffix fallback, ambiguity, traversal rejection), the line-accuracy of
search hits, and the JSON surfaces agents consume.
"""

import io;
import json;
import from contextlib { redirect_stdout }
import from jaclang.cli.guide_store {
    list_guides,
    list_docs,
    get_guide,
    doc_corpora,
    grep_guides
}
import from jaclang.cli.commands.guide { guide }


glob CORPUS_NAMESPACES: list[str] = ["ref", "learn", "tutorial", "internals"];


def _capture_json(fn: any) -> any {
    buf = io.StringIO();
    with redirect_stdout(buf) {
        rc = fn();
    }
    assert rc == 0 , f"guide() exited {rc}; output={buf.getvalue()!r}";
    return json.loads(buf.getvalue());
}


test "bundled docs corpus ships namespaced, described, and non-trivial" {
    docs = list_docs();
    assert len(docs) >= 60 , f"expected a full corpus, got {len(docs)} docs";
    names = {g.name: g for g in docs};
    for expected in [
        "ref/diagnostics",
        "ref/language/foundation",
        "learn/breaking-changes",
        "learn/syntax-cheatsheet",
        "tutorial/language/coding_primer",
        "internals/codebase-guide"
    ] {
        assert expected in names , f"'{expected}' missing from the corpus";
    }
    for g in docs {
        ns = g.name.split("/")[0];
        assert ns in CORPUS_NAMESPACES , f"unexpected namespace on {g.name}";
        assert g.description , f"{g.name} has no description";
        assert g.body , f"{g.name} has an empty body";
        assert not g.body.startswith("---") , f"{g.name} leaked frontmatter";
    }
}


test "doc_corpora groups every doc by namespace in canonical order" {
    corpora = doc_corpora();
    assert [ns for (ns, _) in corpora] == CORPUS_NAMESPACES;
    counts = {ns: len(members) for (ns, members) in corpora};
    assert counts["ref"] >= 25 , f"ref corpus too small: {counts}";
    assert counts["tutorial"] >= 20 , f"tutorial corpus too small: {counts}";
    assert sum(counts.values()) == len(list_docs());
}


test "get_guide resolves exact names, unique suffixes, and skills first" {
    doc = get_guide("ref/diagnostics");
    assert doc is not None and doc.name == "ref/diagnostics";

    by_suffix = get_guide("breaking-changes");
    assert by_suffix is not None , "unique suffix did not resolve";
    assert by_suffix.name == "learn/breaking-changes";

    skill = get_guide("jac-types");
    assert skill is not None and skill.name == "jac-types" , "skill lookup broke";

    assert get_guide("osp") is None , "ambiguous suffix must not resolve";
    assert get_guide("no-such-doc-anywhere") is None;
}


test "get_guide rejects path traversal and junk names" {
    for bad in ["../skills/jac-types", "ref/../../secrets", "..", "", "/"] {
        assert get_guide(bad) is None , f"'{bad}' should not resolve";
    }
}


test "grep_guides hits are line-accurate against the printed body" {
    bodies = {g.name: g.body for g in (list_guides() + list_docs())};
    hits = grep_guides("nearest enclosing binding");
    assert hits , "expected hits for a known docs phrase";
    guides_hit = {h.guide for h in hits};
    assert "learn/breaking-changes" in guides_hit , f"hit guides: {guides_hit}";
    for h in hits {
        if h.line_no == 0 {
            continue;
        }
        line = bodies[h.guide].splitlines()[h.line_no - 1].lower();
        for term in ["nearest", "enclosing", "binding"] {
            assert term in line , f"{h.guide}:{h.line_no} does not contain '{term}'";
        }
    }
}


test "grep_guides honors per-guide and total caps" {
    hits = grep_guides("jac", max_per_guide=2, max_total=10);
    assert len(hits) <= 10;
    body_hits: dict[str, int] = {};
    for h in hits {
        if h.line_no > 0 {
            body_hits[h.guide] = body_hits.get(h.guide, 0) + 1;
        }
    }
    for (name, count) in body_hits.items() {
        assert count <= 2 , f"{name} exceeded max_per_guide: {count}";
    }
    assert grep_guides("") == [];
}


test "guide --json emits the full skill + doc index" {
    payload = _capture_json(lambda { guide(as_json=True); });
    kinds = {entry["kind"] for entry in payload};
    assert kinds == {"skill", "doc"} , f"kinds: {kinds}";
    assert len(payload) == len(list_guides()) + len(list_docs());
    for entry in payload {
        assert entry["name"] and entry["description"] is not None;
    }
}


test "guide <corpus> and guide <doc> JSON surfaces work" {
    listing = _capture_json(lambda { guide(topic="ref", as_json=True); });
    assert "ref/diagnostics" in {entry["name"] for entry in listing};

    doc = _capture_json(lambda { guide(topic="ref/diagnostics", as_json=True); });
    assert doc["name"] == "ref/diagnostics";
    body = str(doc["body"]);
    assert "diagnostic" in body.lower();
}


test "guide --search JSON emits grep hits" {
    hits = _capture_json(lambda { guide(search="walker", as_json=True); });
    assert hits , "expected search hits for 'walker'";
    for h in hits {
        assert set(h.keys()) == {"guide", "line", "text"};
    }
}


test "mcp resources index the docs corpus" {
    import from jaclang.cli.mcp.resources { ResourceProvider }
    provider = ResourceProvider();
    uris = {r["uri"] for r in provider.list_resources()};
    assert "jac://docs/ref/diagnostics" in uris , "docs corpus missing from MCP";
    assert "jac://guide/jac-types" in uris , "skill guides missing from MCP";
    content = provider.read_resource("jac://docs/ref/diagnostics");
    assert "diagnostic" in content.lower();
}
