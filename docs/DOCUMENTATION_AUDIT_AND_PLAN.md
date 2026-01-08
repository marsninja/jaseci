# Jac Documentation Audit and Overhaul Plan

**Prepared by**: Claude Opus 4.5 (Documentation Analysis Agent)
**Date**: January 7, 2026
**Scope**: jaclang, jac-client, jac-scale, jac-byllm

---

## Executive Summary

This document presents a comprehensive audit of the Jac documentation, identifying inaccuracies, redundancies, gaps, and organizational issues. Based on deep investigation of the actual codebase and CLI capabilities, this plan provides a roadmap for a complete documentation overhaul.

---

## Part 1: Current Documentation Structure Analysis

### 1.1 Current Navigation Hierarchy

```
docs/
├── Learn/
│   ├── Getting Started (7 pages - overlapping content)
│   ├── The Jac Book (20 chapters + Specifications + Misc Docs)
│   ├── Programming 'by' LLM (9 pages)
│   ├── Scale-Native Programming (jac-lens + deprecated jac-cloud)
│   ├── Jac Client (17+ pages)
│   ├── Jac Scale (4 pages)
│   ├── Tooling (7 pages)
│   └── Examples (8 tutorials)
├── Full Jac Specification (59 pages - reference)
├── Contributor Hub/
│   ├── Release Notes
│   ├── Breaking Changes
│   ├── Leaderboard
│   └── Internals
├── Jac Playground
└── Jac GPT (external link)
```

### 1.2 Issues with Current Structure

| Issue | Description | Severity |
|-------|-------------|----------|
| **Redundant Quickstarts** | 4+ "getting started" style pages with overlapping content | High |
| **Deprecated Content** | jac-cloud marked deprecated but still prominent in navigation | High |
| **Inconsistent Naming** | "Scale-Native" vs "Jac Scale" vs "jac-scale" terminology | Medium |
| **Buried Features** | Critical CLI commands scattered across multiple pages | High |
| **Outdated Commands** | Documentation mentions `jac init` and `jac clean` that don't exist | Critical |
| **Missing Plugin Docs** | No documentation for `jac plugins` management system | High |
| **Jac Book Bloat** | 20 chapters + misc docs becomes unwieldy | Medium |
| **Examples Scattered** | Examples in multiple locations (Learn, Jac Book, Examples section) | Medium |

---

## Part 2: Inaccuracies Found

### 2.1 CLI Command Discrepancies

| Documented | Actual | Issue |
|------------|--------|-------|
| `jac init` | `jac create` | **Wrong command name** - docs mention `jac init` in project_config.md |
| `jac clean` | Does not exist | **Command doesn't exist** - mentioned in cli.md line 103-111 |
| `jac format` params | Different signature | Docs show `outfile`, `debug` but actual has `to_screen`, `fix` |
| `jac run` params | Different signature | Docs incomplete - missing `-s/--session` parameter |
| `jac enter` signature | Wrong order | Docs show `<file> <entrypoint> <args>` but `-e` is required flag |

### 2.2 Feature Documentation Gaps

| Feature | Status in Docs | Actual Capability |
|---------|---------------|-------------------|
| `jac plugins` | Basic mention | Full plugin management: enable/disable/list/verbose |
| `jac script` | Not documented | Run custom scripts from jac.toml |
| `jac get_object` | Not documented | Retrieve object by ID from session |
| `jac dot` | Not documented | Generate DOT graph visualization |
| `jac gen_parser` | Not documented | Generate parser (internal tool) |
| `jac tool ir cfg.` | Not documented | Control flow graph visualization |
| `jac destroy` | Not documented | Remove Kubernetes deployment (jac-scale) |
| Environment profiles | Not documented | `JAC_PROFILE` and `[environments]` in jac.toml |

### 2.3 jac.toml Configuration Gaps

**Documented but with outdated info:**

- `[serve].cl_route_prefix` and `[serve].base_route_app` - recently added, not fully documented
- Environment variable interpolation syntax (`${VAR:-default}`) - mentioned but incomplete
- Plugin-specific configuration sections - structure unclear

**Completely undocumented:**

- `[plugins].discovery` modes
- Environment profiles (`[environments.dev]`, etc.)
- Git dependencies syntax
- `[build].dir` for centralized artifact storage

### 2.4 jac-scale Inaccuracies

| Issue | Details |
|-------|---------|
| **jac-cloud confusion** | Docs present jac-cloud as current, but jac-scale is the replacement |
| **Deployment modes** | Docs don't explain the two deployment modes (with/without Docker build) |
| **Memory hierarchy** | Undocumented 3-tier memory system (L1/L2/L3) |
| **Configuration** | Many K8s environment variables undocumented |
| **SSO** | Google OAuth setup not fully documented |

### 2.5 jac-client Inaccuracies

| Issue | Details |
|-------|---------|
| **Export syntax** | Version 0.2.4+ requires `:pub` but not clearly stated everywhere |
| **Import patterns** | Many documented patterns are "not yet implemented" |
| **Routing hooks** | `useParams`, `useLocation` exist but minimally documented |
| **Package management** | `jac add --cl` workflow not fully explained |

### 2.6 jac-byllm Inaccuracies

| Issue | Details |
|-------|---------|
| **MTIR** | Multi-Turn Interaction Runtime not documented at all |
| **Configuration** | `jac.toml` plugin configuration not fully documented |
| **MockLLM** | Testing with MockLLM not documented |
| **ReAct** | Tool-based ReAct pattern under-documented |

---

## Part 3: Redundancies Identified

### 3.1 Content Overlap

| Content Type | Locations | Recommendation |
|--------------|-----------|----------------|
| **Hello World** | installation.md, chapter_1.md, tour.md | Consolidate to one |
| **OSP Intro** | quickstart.md, chapter_8.md, dspfoundation.md, nodes_and_edges.md | Consolidate |
| **Walkers** | quickstart.md, chapter_10.md, walkers.md | Single authoritative source |
| **by llm basics** | with_llm.md, quickstart.md (byllm), chapter_4.md, chapter_5.md | Deduplicate |
| **Installation** | installation.md, chapter_1.md, jac-client README | Single source |
| **jac serve** | jac_serve.md, cli.md, jac-cloud intro, jac-scale README | Consolidate |
| **Project structure** | project_config.md, multiple READMEs | Single reference |

### 3.2 Deprecated vs Current

| Deprecated | Replacement | Action Needed |
|------------|-------------|---------------|
| jac-cloud (entire section) | jac-scale | Remove or archive jac-cloud, expand jac-scale |
| `createSignal()` | `useState()` | Update jac-client examples |
| `onMount()` | `useEffect([], [])` | Update jac-client examples |
| Old import syntax | New `cl import from` | Standardize across docs |

---

## Part 4: Documentation Gaps

### 4.1 Missing Core Documentation

| Topic | Priority | Notes |
|-------|----------|-------|
| **Complete CLI Reference** | Critical | Every command with all parameters |
| **jac.toml Full Reference** | Critical | Every section with all options |
| **Plugin Development Guide** | High | How to create custom plugins |
| **Plugin Management** | High | Using `jac plugins` command |
| **Memory/Persistence Deep Dive** | High | TieredMemory, ShelfMemory, etc. |
| **Debugging Guide** | High | All `jac tool ir` commands |
| **Access Control System** | Medium | Multi-root permissions |
| **Concurrency (flow/wait)** | Medium | Async patterns in Jac |

### 4.2 Missing jac-scale Documentation

| Topic | Priority |
|-------|----------|
| Memory hierarchy (L1/L2/L3) architecture | Critical |
| All K8s environment variables | High |
| Docker build vs direct deployment | High |
| SSO setup (Google OAuth) | Medium |
| Horizontal Pod Autoscaling configuration | Medium |
| Custom Kubernetes configuration | Medium |
| Troubleshooting guide | Medium |

### 4.3 Missing jac-client Documentation

| Topic | Priority |
|-------|----------|
| Complete routing hooks reference | High |
| All implemented import patterns | High |
| CSS handling pipeline | Medium |
| Asset serving details | Medium |
| Hot Module Replacement status | Medium |
| TypeScript advanced patterns | Medium |

### 4.4 Missing jac-byllm Documentation

| Topic | Priority |
|-------|----------|
| MTIR (Multi-Turn Interaction Runtime) | High |
| Complete configuration reference | High |
| MockLLM for testing | High |
| ReAct pattern deep dive | Medium |
| Custom model class creation | Medium |
| Video/multimodal examples | Medium |
| Error handling and fallbacks | Medium |

---

## Part 5: Proposed New Documentation Structure

### 5.1 Recommended Navigation

```
docs/
├── Getting Started/
│   ├── Introduction                    # What is Jac? (from tour.md)
│   ├── Installation                    # Single authoritative guide
│   ├── Hello World                     # First program
│   ├── Quickstart: OSP in 10 Minutes   # Condensed OSP intro
│   └── IDE Setup                       # VS Code, Cursor
│
├── Language Guide/
│   ├── Syntax & Basics/
│   │   ├── Python Superset             # How Jac extends Python
│   │   ├── Variables & Types           # Type system
│   │   ├── Control Flow                # if/for/while/match
│   │   ├── Functions & Decorators      # def, async, decorators
│   │   └── Imports & Modules           # Import system
│   │
│   ├── Object-Spatial Programming/
│   │   ├── Introduction to OSP         # Paradigm explanation
│   │   ├── Nodes & Edges               # Graph primitives
│   │   ├── Walkers & Abilities         # Computation agents
│   │   ├── Graph Operations            # Traversal, filtering
│   │   ├── Advanced Patterns           # Multi-hop, BFS/DFS
│   │   └── OSP Specification           # Formal reference
│   │
│   └── Enhanced OOP/
│       ├── Objects & Classes           # obj vs class
│       ├── Access Control              # :pub, :priv, :protect
│       └── Implementation Files        # .impl.jac pattern
│
├── AI Integration (byLLM)/
│   ├── Introduction to MTP             # Meaning Typed Programming
│   ├── Quick Start                     # Basic examples
│   ├── The "by" Syntax                 # Full syntax reference
│   ├── Type-Safe Outputs               # Custom types, enums
│   ├── Multimodal (Images/Video)       # Vision capabilities
│   ├── Agentic AI & ReAct              # Tool calling, agents
│   ├── Configuration                   # jac.toml, environment
│   ├── Python Library Mode             # Using byLLM in Python
│   └── Examples Gallery                # Curated examples
│
├── Full-Stack Development (jac-client)/
│   ├── Getting Started                 # Setup, jac create --cl
│   ├── Components & JSX                # React-style components
│   ├── State Management                # useState, useEffect, etc.
│   ├── Routing                         # SPA navigation
│   ├── Styling Guide                   # All 6 methods
│   ├── Backend Integration             # spawn, walkers as API
│   ├── Authentication                  # jacLogin, jacSignup
│   ├── Package Management              # jac add --cl
│   ├── TypeScript                      # TS integration
│   ├── File Organization               # Project structure
│   └── Advanced Configuration          # Vite, custom builds
│
├── Production & Scaling (jac-scale)/
│   ├── Introduction                    # What jac-scale provides
│   ├── Quick Start                     # jac serve, jac scale
│   ├── Memory Architecture             # L1/L2/L3 tiers
│   ├── API Generation                  # Walkers as REST endpoints
│   ├── Authentication & SSO            # JWT, Google OAuth
│   ├── Kubernetes Deployment           # Full K8s guide
│   ├── Configuration Reference         # All options
│   └── Migration from jac-cloud        # Transition guide
│
├── CLI Reference/
│   ├── Overview                        # All commands summary
│   ├── jac run                         # With all parameters
│   ├── jac serve                       # Server options
│   ├── jac scale                       # K8s deployment
│   ├── jac create                      # Project scaffolding
│   ├── jac test                        # Testing
│   ├── jac build                       # Compilation
│   ├── jac check                       # Type checking
│   ├── jac format                      # Code formatting
│   ├── jac plugins                     # Plugin management
│   ├── jac tool                        # Developer tools
│   ├── jac dot                         # Graph visualization
│   ├── Package Management              # add, remove, install
│   └── Other Commands                  # enter, get_object, etc.
│
├── Configuration/
│   ├── jac.toml Complete Reference     # Every option documented
│   ├── Environment Variables           # All env vars
│   ├── Plugin Configuration            # Per-plugin settings
│   └── Environment Profiles            # Dev/prod configs
│
├── Testing & Debugging/
│   ├── Testing Framework               # Writing tests
│   ├── Debugging Tools                 # jac tool ir, etc.
│   ├── Graph Visualization             # printgraph, dot output
│   └── Troubleshooting Guide           # Common issues
│
├── Advanced Topics/
│   ├── Plugin Development              # Creating plugins
│   ├── Persistence Deep Dive           # Memory tiers
│   ├── Access Control                  # Multi-user, permissions
│   ├── Concurrency                     # flow/wait, async
│   ├── Performance Optimization        # Best practices
│   └── Python Interop                  # Library mode
│
├── The Jac Book/                       # Keep as learning path
│   └── [Restructured 20 chapters]      # Reference new sections
│
├── Language Specification/
│   └── [All 59 reference pages]        # Keep as formal spec
│
├── Examples/
│   ├── Beginner                        # Hello world to simple apps
│   ├── Intermediate                    # Full-stack apps
│   ├── Advanced                        # Complex AI applications
│   └── Real-World                      # Production examples
│
├── Contributor Hub/
│   ├── Contributing Guide
│   ├── Release Notes
│   ├── Breaking Changes
│   └── Architecture Docs
│
└── Tools/
    ├── VS Code Extension
    ├── Jac Playground
    ├── Jac Lens
    └── Jac GPT
```

### 5.2 Content Migration Matrix

| Current Location | New Location | Action |
|------------------|--------------|--------|
| learn/tour.md | Getting Started/Introduction | Revise |
| learn/installation.md | Getting Started/Installation | Keep |
| learn/quickstart.md | Getting Started/Quickstart: OSP | Revise |
| jac_book/chapter_1.md | Getting Started/Hello World | Extract |
| learn/superset_python.md | Language Guide/Syntax & Basics | Keep |
| learn/data_spatial/*.md | Language Guide/OSP | Merge |
| learn/jac-byllm/*.md | AI Integration | Reorganize |
| jac-client/*.md | Full-Stack Development | Reorganize |
| jac-scale/*.md | Production & Scaling | Expand |
| learn/jac-cloud/*.md | Archive/Legacy | Archive |
| learn/tools/*.md | CLI Reference + Tools | Split |
| jac_book/*.md | The Jac Book | Keep with cross-refs |
| learn/jac_ref/*.md | Language Specification | Keep |

---

## Part 6: Specific Fixes Required

### 6.1 Immediate Corrections (Critical)

1. **cli.md**: Remove `jac clean` documentation (command doesn't exist)
2. **project_config.md**: Change `jac init` to `jac create`
3. **cli.md**: Fix `jac format` parameters to match actual CLI
4. **cli.md**: Fix `jac enter` syntax (requires `-e` flag)
5. **cli.md**: Add complete `jac plugins` documentation
6. **mkdocs.yml**: Mark jac-cloud section clearly as deprecated/archived

### 6.2 High Priority Additions

1. Create complete CLI reference with all commands
2. Document all `jac.toml` configuration options
3. Add jac-scale memory hierarchy documentation
4. Add jac-byllm MTIR documentation
5. Add `jac plugins` management guide
6. Add debugging tools guide (`jac tool ir *`)

### 6.3 Content Consolidation

1. Merge all OSP introductions into single authoritative guide
2. Merge all installation guides into single page
3. Merge all quickstart materials
4. Consolidate walker documentation
5. Consolidate by-llm introductions

### 6.4 Deprecation Handling

1. Archive jac-cloud content (keep for legacy reference)
2. Create migration guide from jac-cloud to jac-scale
3. Update all jac-cloud references to point to jac-scale
4. Remove jac-cloud from main navigation

---

## Part 7: Implementation Phases

### Phase 1: Critical Fixes (Week 1-2)

- [ ] Fix all CLI command inaccuracies
- [ ] Update jac.toml documentation
- [ ] Archive jac-cloud section
- [ ] Add missing plugin documentation
- [ ] Fix navigation to remove deprecated content

### Phase 2: Structure Reorganization (Week 3-4)

- [ ] Create new navigation structure in mkdocs.yml
- [ ] Create stub pages for new sections
- [ ] Migrate existing content to new locations
- [ ] Add redirects for old URLs

### Phase 3: Content Expansion (Week 5-8)

- [ ] Write complete CLI reference
- [ ] Write complete jac.toml reference
- [ ] Expand jac-scale documentation
- [ ] Expand jac-byllm documentation
- [ ] Add debugging and testing guides

### Phase 4: Content Consolidation (Week 9-10)

- [ ] Merge redundant pages
- [ ] Update cross-references
- [ ] Ensure consistent terminology
- [ ] Add missing examples

### Phase 5: Polish & Review (Week 11-12)

- [ ] Technical review of all pages
- [ ] Grammar and style consistency
- [ ] Add navigation improvements
- [ ] Test all code examples
- [ ] Update Jac Book to reference new sections

---

## Part 8: Style Guide Recommendations

### 8.1 Terminology Standards

| Use This | Not This |
|----------|----------|
| jac-scale | Jac Scale, JacScale |
| jac-client | Jac Client, JacClient |
| byLLM | byllm, by-llm, ByLLM |
| Object-Spatial Programming (OSP) | Data Spatial, Object Spatial |
| jac.toml | jac.TOML, JAC.toml |
| `jac serve` | jac-serve, jacserve |

### 8.2 Code Example Standards

- All examples should be runnable
- Use consistent formatting
- Include expected output
- Provide both Jac and Python versions where applicable
- Mark version-specific features clearly

### 8.3 Page Structure Standards

1. **Title**: Clear, concise
2. **Overview**: 2-3 sentences explaining the topic
3. **Prerequisites**: What reader should know
4. **Content**: Main content with examples
5. **Common Patterns**: Best practices
6. **Troubleshooting**: Common issues
7. **Next Steps**: Links to related content

---

## Appendix A: All Actual CLI Commands

Based on investigation, here are ALL available jac CLI commands:

```
jac --help
jac --version

# Core Commands (jaclang built-in)
jac run <file> [-s SESSION] [-m/--main] [-c/--cache]
jac build <file> [-t/--typecheck]
jac check <paths...> [-p/--print_errs] [-w/--warnonly]
jac format <paths...> [-t/--to_screen] [-f/--fix]
jac test [file] [-t TEST_NAME] [-f FILTER] [-x/--xit] [-m MAXFAIL] [-d DIR] [-v]
jac enter <file> -e ENTRYPOINT [-s SESSION] [-m/--main] [-r ROOT] [-n NODE] [args...]
jac debug <file> [-m/--main] [-c/--cache]
jac lsp
jac dot <file> [connections...] [-s SESSION] [-i INITIAL] [-d DEPTH] [-t/--traverse]
       [-b/--bfs] [-e EDGE_LIMIT] [-n NODE_LIMIT] [-sa SAVETO] [-to/--to_screen] [-f FORMAT]
jac get_object <file> -i ID [-s SESSION] [-m/--main]
jac py2jac <file>
jac jac2py <file>
jac js <file>
jac tool <tool_name> [args...]

# Package Management
jac create <name> [-f/--force] [-c/--cl] [-s/--skip] [-v/--verbose]
jac install [-d/--dev] [-v/--verbose]
jac add [packages...] [-d/--dev] [-g GIT] [-c/--cl] [-v/--verbose]
jac remove [packages...] [-d/--dev] [-c/--cl]
jac script <name> [-l/--list_scripts]

# Plugin Management
jac plugins [action] [names...] [-v/--verbose]
# Actions: list, disable, enable, disabled

# Internal
jac gen_parser

# jac-scale Plugin Commands
jac serve <file> [-s SESSION] [-p PORT] [-m/--main] [-f/--faux]
jac scale <file> [-b/--build]
jac destroy <file>
```

---

## Appendix B: Complete jac.toml Configuration Schema

```toml
[project]
name = "string"
version = "string"
description = "string"
authors = ["string"]
license = "string"
readme = "string"
jac-version = "string"
entry-point = "string"

[project.urls]
homepage = "string"
repository = "string"

[run]
session = "string"
main = true|false
cache = true|false

[build]
typecheck = true|false
dir = ".jac"

[test]
directory = "string"
filter = "string"
verbose = true|false
fail_fast = true|false
max_failures = 0

[serve]
port = 8000
session = "string"
main = true|false
cl_route_prefix = "cl"
base_route_app = ""

[format]
outfile = "string"
fix = true|false

[check]
print_errs = true|false
warnonly = true|false

[dot]
depth = -1
traverse = true|false
bfs = true|false
edge_limit = 512
node_limit = 512
format = "dot"

[cache]
enabled = true|false
dir = ".jac_cache"

[plugins]
discovery = "auto"|"manual"|"disabled"
enabled = ["plugin-name"]
disabled = ["plugin-name"]

[plugins.byllm]
# byLLM configuration

[plugins.byllm.model]
default_model = "gpt-4o-mini"
api_key = ""
base_url = ""
proxy = false
verbose = false

[plugins.byllm.call_params]
temperature = 0.7
max_tokens = 0

[plugins.byllm.litellm]
local_cost_map = true
drop_params = true

[plugins.scale]
# jac-scale configuration

[plugins.scale.jwt]
secret = "string"
algorithm = "HS256"
exp_delta_days = 7

[plugins.scale.sso]
host = "http://localhost:8000/sso"

[plugins.scale.sso.google]
client_id = ""
client_secret = ""

[plugins.scale.database]
mongodb_uri = ""
redis_url = ""
shelf_db_path = ".jac/data/anchor_store.db"

[plugins.scale.kubernetes]
app_name = "jaseci"
docker_image_name = ""
docker_username = ""
docker_password = ""
namespace = "default"
container_port = 8000
node_port = 30001
mongodb_enabled = true
redis_enabled = true

[plugins.scale.server]
port = 8000
host = "0.0.0.0"

[plugins.client]
# jac-client configuration

[plugins.client.vite]
# Vite configuration

[plugins.client.ts]
# TypeScript configuration

[plugins.client.package]
# Package metadata

[environment]
default_profile = "string"

[environments.development]
# Development-specific overrides

[environments.production]
inherits = "development"
# Production-specific overrides

[dependencies]
package_name = ">=version"

[dev-dependencies]
package_name = ">=version"

[dependencies.git]
package_name = { git = "url", branch = "main" }

[dependencies.npm]
package_name = "^version"

[dependencies.npm.dev]
package_name = "^version"

[scripts]
script_name = "jac command"
```

---

## Conclusion

This audit reveals significant opportunities to improve the Jac documentation. The primary issues are:

1. **Inaccurate CLI documentation** with non-existent commands
2. **Deprecated content** (jac-cloud) still prominent
3. **Redundant content** across multiple pages
4. **Missing documentation** for critical features
5. **Disorganized structure** making it hard to find information

The proposed reorganization creates a cleaner hierarchy that separates:

- Learning content (Getting Started, Language Guide)
- Feature documentation (AI, Full-Stack, Production)
- Reference material (CLI, Configuration, Specification)
- Advanced topics (Plugin development, Performance)

Implementation should proceed in phases, prioritizing critical fixes first before restructuring and expansion.
