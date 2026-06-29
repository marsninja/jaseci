import os;
import from pathlib { Path }
import from jaclang.cli.guide_store { list_guides as gs_list, get_guide as gs_get }

glob _PROJECT_MAP_SKIP_AT_FILES = 250,
     _PROJECT_MAP_CHAR_CAP = 12000,
     _PROJECT_MAP_SAMPLE_ROWS = 80,
     _PROJECT_MAP_BUCKET_ROWS = 8,
     _PROJECT_MAP_SCAN_SKIP_DIRS: set[str] = {
         ".git",
         ".hg",
         ".svn",
         ".venv",
         ".jac",
         "node_modules",
         "__pycache__",
         ".mypy_cache",
         ".pytest_cache",
         ".ruff_cache",
         "build",
         "dist"
     };

sem GuideTools.search_guides = "Search the bundled Jac reference guides; returns matching guide names and descriptions ranked by relevance. Matches any word in the query, so several keywords broaden the search.";
sem GuideTools.search_guides.keyword = "Keywords to search guide names, descriptions, and bodies for.";
impl GuideTools.search_guides(keyword: str) -> str {
    words = [
        w
        for w in keyword.lower().split()
        if w
    ];
    if not words {
        return "(empty search)";
    }
    scored: list[tuple[int, str]] = [];
    for g in gs_list() {
        haystack = f"{g.name}\n{g.description}\n{g.body}".lower();
        hits = sum(
            [
                1
                for w in words
                if w in haystack
            ]
        );
        if hits > 0 {
            scored.append((-hits, f"{g.name}: {g.description}"));
        }
    }
    if not scored {
        return f"(no guides match '{keyword}')";
    }
    scored.sort();
    return "\n".join([line for (_, line) in scored]);
}

sem GuideTools.read_guide = "Read a bundled Jac reference guide in full -- the authoritative spec for writing correct, idiomatic Jac.";
sem GuideTools.read_guide.name = "Exact guide name, e.g. 'jac-walker-patterns'.";
impl GuideTools.read_guide(name: str) -> str {
    guide = gs_get(name);
    if guide is None {
        available = ", ".join([g.name for g in gs_list()]);
        return f"ERROR: no guide named '{name}'. Available guides: {available}";
    }
    return truncate(guide.body, 16000);
}

sem SemanticTools.find_symbol = "Look up a Jac symbol (node, walker, edge, obj, enum, ability, ...) by name via the compiler's symbol table. Returns its exact definition site, fields, abilities, base classes, and every place it is used. This is precise -- unlike grep it never matches a comment or an unrelated identifier. Prefer this over grep whenever you know the name of the thing you are looking for.";
sem SemanticTools.find_symbol.name = "The symbol name to look up, e.g. 'User' or 'make_user'.";
impl SemanticTools.find_symbol(name: str) -> str {
    ci = self.ws.code_intel();
    if ci is None {
        return "ERROR: code intelligence is unavailable in this session.";
    }
    hits = ci.lookup(name);
    if not hits {
        return f"No Jac symbol named '{name}' is defined in this project.";
    }
    out: list[str] = [];
    for info in hits {
        out.append(str(info.render()));
    }
    uses = [
        r
        for r in ci.references(name)
        if r.role == "use"
    ];
    if uses {
        out.append(f"\nused in {len(uses)} place(s):");
        for r in uses[:25] {
            out.append("  " + str(r.render()));
        }
    }
    return "\n".join(out);
}

sem SemanticTools.find_uses = "List every definition and use of a symbol across the whole project, computed from the compiler's def/use chains. Use this before renaming or changing a symbol to see exactly what it touches.";
sem SemanticTools.find_uses.name = "The symbol name whose references to list.";
impl SemanticTools.find_uses(name: str) -> str {
    ci = self.ws.code_intel();
    if ci is None {
        return "ERROR: code intelligence is unavailable in this session.";
    }
    refs = ci.references(name);
    if not refs {
        return f"No definitions or uses of '{name}' were found.";
    }
    lines: list[str] = [];
    for r in refs {
        lines.append(f"{r.role}  {r.render()}");
    }
    return "\n".join(lines);
}

sem SemanticTools.project_map = "Show every node, walker, edge, and object archetype in the project with its location -- a structural overview built from the compiler, not a directory listing. Useful for unfamiliar small/medium projects; on large monorepos, narrow scope first with list_dir/grep or run from a package subdirectory.";
impl SemanticTools.project_map -> str {
    ci = self.ws.code_intel();
    if ci is None {
        return "ERROR: code intelligence is unavailable in this session.";
    }
    base_dir = str(ci?.proj_dir or self.ws.cwd or os.getcwd());
    if bool(ci?.lazy) and not bool(ci.is_loaded()) {
        found: list[str] = [];
        base = Path(os.path.normpath(base_dir));
        if base.exists() {
            for p in sorted(base.rglob("*.jac")) {
                if any(
                    [
                        part in _PROJECT_MAP_SCAN_SKIP_DIRS or part.startswith(".")
                        for part in p.parts
                    ]
                ) {
                    continue;
                }
                name = p.name;
                if name.endswith(".impl.jac") or name.endswith(".test.jac") {
                    continue;
                }
                found.append(str(p));
            }
        }
        if len(found) > _PROJECT_MAP_SKIP_AT_FILES {
            buckets: dict[str, int] = {};
            for f in found {
                rel = os.path.relpath(f, base_dir);
                parts = rel.split(os.sep);
                bucket = str(parts[0] or ".") if parts else ".";
                buckets[bucket] = int(buckets.get(bucket, 0) or 0) + 1;
            }
            lines = [
                f"Project map skipped: this workspace has {len(
                    found
                )} Jac modules under {base_dir}.",
                "Building the full structural map here would be slow and would flood the model context."
            ];
            if buckets {
                lines.append("Top areas by module count:");
                shown = 0;
                for bucket in sorted(buckets) {
                    lines.append(f"- {bucket}: {int(buckets.get(bucket, 0) or 0)}");
                    shown += 1;
                    if shown >= _PROJECT_MAP_BUCKET_ROWS {
                        break;
                    }
                }
            }
            lines.append(
                "Narrow scope first with list_dir/grep/find_symbol, or run `jac ai` from the package subdirectory you actually want to change."
            );
            return "\n".join(lines);
        }
    }
    archs: list = list(ci.archetypes());
    if not archs {
        return "(no nodes, walkers, edges, or objects found in the project)";
    }
    rows: list[str] = [];
    kind_counts: dict[str, int] = {};
    bucket_counts: dict[str, int] = {};
    files: set[str] = set();
    for a in archs {
        kind = str(a.kind or "?");
        file = str(a.file or "");
        rows.append(f"{kind:7} {a.name}    [{file}:{a.line}]");
        kind_counts[kind] = int(kind_counts.get(kind, 0) or 0) + 1;
        if file {
            files.add(file);
            rel = os.path.relpath(file, base_dir);
            parts = rel.split(os.sep);
            bucket = str(parts[0] or ".") if parts else ".";
            bucket_counts[bucket] = int(bucket_counts.get(bucket, 0) or 0) + 1;
        }
    }
    full = "\n".join(sorted(rows));
    if len(full) <= _PROJECT_MAP_CHAR_CAP {
        return full;
    }
    lines = [
        f"Project map summary: {len(rows)} archetypes across {len(files)} files.",
        f"The full map is {len(full)} chars, so it is summarized here."
    ];
    if kind_counts {
        lines.append(
            "Kinds: " + ", ".join(
                [
                    f"{kind}={int(kind_counts.get(kind, 0) or 0)}"
                    for kind in sorted(kind_counts)
                ]
            )
        );
    }
    if bucket_counts {
        lines.append("Top areas by archetype count:");
        shown = 0;
        for bucket in sorted(bucket_counts) {
            lines.append(f"- {bucket}: {int(bucket_counts.get(bucket, 0) or 0)}");
            shown += 1;
            if shown >= _PROJECT_MAP_BUCKET_ROWS {
                break;
            }
        }
    }
    lines.append("Sample rows:");
    lines.extend(sorted(rows)[:_PROJECT_MAP_SAMPLE_ROWS]);
    return truncate("\n".join(lines), _PROJECT_MAP_CHAR_CAP);
}

sem SemanticTools.find_walkers = "Find every walker entry point that traverses a given node type -- an Object-Spatial query the compiler answers from walker entry signatures. Use this to see how a node is visited.";
sem SemanticTools.find_walkers.node_type = "The node archetype name, e.g. 'User'.";
impl SemanticTools.find_walkers(node_type: str) -> str {
    ci = self.ws.code_intel();
    if ci is None {
        return "ERROR: code intelligence is unavailable in this session.";
    }
    eps = ci.walkers_visiting(node_type);
    if not eps {
        return f"No walkers traverse a '{node_type}' node.";
    }
    lines: list[str] = [];
    for ep in eps {
        lines.append(str(ep.render()));
    }
    return "\n".join(lines);
}

sem SemanticTools.context_slice = "Get a typed context slice for a symbol: its definition, the types it depends on, and where it is used -- a focused, compiler-accurate neighbourhood to read instead of opening whole files.";
sem SemanticTools.context_slice.name = "The symbol to build a context slice around.";
impl SemanticTools.context_slice(name: str) -> str {
    ci = self.ws.code_intel();
    if ci is None {
        return "ERROR: code intelligence is unavailable in this session.";
    }
    return str(ci.slice_for(name).render());
}
