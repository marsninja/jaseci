# Jac Documentation Complete Rewrite - Phase Plan

**Based on**: DOCUMENTATION_AUDIT_AND_PLAN.md
**Goal**: Clean, well-organized, accurate documentation for the Jac ecosystem

---

## Overview

This plan outlines a complete documentation rewrite in 6 phases, designed to be executed incrementally while keeping the documentation functional throughout.

```
Phase 0: Preparation & Foundation
    ↓
Phase 1: Critical Fixes & Cleanup
    ↓
Phase 2: New Structure & Navigation
    ↓
Phase 3: Core Content Rewrite
    ↓
Phase 4: Plugin Documentation Expansion
    ↓
Phase 5: Polish, Examples & Launch
```

---

## Phase 0: Preparation & Foundation

**Goal**: Set up infrastructure and establish standards before making changes

### Tasks

- [ ] **0.1 Create documentation style guide**
  - Terminology standards (jac-scale, byLLM, OSP, etc.)
  - Code example formatting requirements
  - Page structure template
  - Voice and tone guidelines

- [ ] **0.2 Set up documentation testing**
  - Script to validate all code examples compile/run
  - Link checker for internal/external links
  - Spell checker configuration

- [ ] **0.3 Create redirect mapping**
  - Map all current URLs to planned new URLs
  - Configure mkdocs redirects plugin
  - Document breaking URL changes

- [ ] **0.4 Archive current documentation**
  - Create tagged backup of current state
  - Document current structure for reference

- [ ] **0.5 Set up staging environment**
  - Separate branch for documentation work
  - Preview deployment for review

### Deliverables

- `docs/STYLE_GUIDE.md`
- `docs/scripts/validate_examples.py`
- `docs/URL_REDIRECTS.md`
- Git tag: `docs-v1-archive`
- Documentation staging branch

---

## Phase 1: Critical Fixes & Cleanup

**Goal**: Fix all inaccuracies and remove deprecated content without restructuring

### Tasks

#### 1.1 Fix CLI Documentation Errors

- [ ] Remove `jac clean` documentation (doesn't exist)
- [ ] Change `jac init` to `jac create` everywhere
- [ ] Fix `jac format` parameters (`to_screen`, `fix` not `outfile`, `debug`)
- [ ] Fix `jac enter` syntax (requires `-e` flag)
- [ ] Fix `jac run` to include `-s/--session` parameter
- [ ] Add `jac plugins` complete documentation
- [ ] Add `jac script` documentation
- [ ] Add `jac dot` documentation
- [ ] Add `jac get_object` documentation
- [ ] Add `jac destroy` documentation (jac-scale)

#### 1.2 Fix jac.toml Documentation

- [ ] Add `[serve].cl_route_prefix` and `[serve].base_route_app`
- [ ] Document environment variable interpolation fully
- [ ] Add `[plugins].discovery` options
- [ ] Add `[environments]` section documentation
- [ ] Add `[build].dir` documentation
- [ ] Document git dependencies syntax

#### 1.3 Handle Deprecated Content

- [ ] Add prominent deprecation banner to all jac-cloud pages
- [ ] Update mkdocs.yml to clearly mark jac-cloud as "(Deprecated)"
- [ ] Add "Migration to jac-scale" callout on each jac-cloud page
- [ ] Remove jac-cloud from primary navigation flow
- [ ] Update all internal links pointing to jac-cloud

#### 1.4 Fix Version-Specific Issues

- [ ] Clarify jac-client 0.2.4+ export requirements (`:pub`)
- [ ] Mark deprecated hooks (`createSignal`, `onMount`) in jac-client docs
- [ ] Update examples to use current syntax

### Deliverables

- All CLI docs accurate
- All jac.toml docs complete
- jac-cloud clearly deprecated
- All code examples verified working

---

## Phase 2: New Structure & Navigation

**Goal**: Implement new documentation hierarchy without losing content

### Tasks

#### 2.1 Create New Directory Structure

```
docs/docs/
├── getting-started/
│   ├── index.md
│   ├── installation.md
│   ├── hello-world.md
│   ├── quickstart-osp.md
│   └── ide-setup.md
├── language/
│   ├── syntax/
│   ├── osp/
│   └── oop/
├── ai-integration/
│   └── [byllm content]
├── full-stack/
│   └── [jac-client content]
├── production/
│   └── [jac-scale content]
├── cli/
│   └── [command reference]
├── configuration/
│   └── [jac.toml reference]
├── testing-debugging/
├── advanced/
├── jac-book/
│   └── [keep existing]
├── specification/
│   └── [keep existing]
├── examples/
├── contributing/
└── archive/
    └── jac-cloud/
```

#### 2.2 Update mkdocs.yml Navigation

- [ ] Create new `nav:` structure matching above
- [ ] Set up section landing pages (index.md for each)
- [ ] Configure navigation tabs
- [ ] Add breadcrumbs

#### 2.3 Create Stub Pages

- [ ] Create index.md for each new section
- [ ] Add "Coming Soon" or redirect for incomplete pages
- [ ] Ensure all navigation links work

#### 2.4 Migrate Existing Content (No Rewriting)

- [ ] Move files to new locations
- [ ] Update internal links
- [ ] Add redirects for old URLs
- [ ] Verify no broken links

### Deliverables

- New directory structure in place
- Updated mkdocs.yml
- All existing content accessible at new URLs
- Redirects working for old URLs

---

## Phase 3: Core Content Rewrite

**Goal**: Rewrite foundational documentation with accurate, consolidated content

### Tasks

#### 3.1 Getting Started Section (New)

- [ ] **Introduction** - What is Jac? (consolidate from tour.md, jac_book/index.md)
  - Jac's purpose and philosophy
  - Key differentiators (OSP, AI-first, Python superset)
  - When to use Jac

- [ ] **Installation** - Single authoritative guide
  - Requirements (Python 3.12+)
  - pip install
  - Virtual environment setup
  - Verification steps

- [ ] **Hello World** - First program
  - Simple example with explanation
  - Running with `jac run`

- [ ] **Quickstart: OSP in 10 Minutes**
  - Condensed OSP tutorial
  - Nodes, edges, walkers basics
  - Working example

- [ ] **IDE Setup**
  - VS Code extension
  - Cursor setup
  - Key features (highlighting, debugging, graph viz)

#### 3.2 Language Guide: Syntax & Basics

- [ ] **Python Superset** - How Jac extends Python
- [ ] **Variables & Types** - Type system, annotations
- [ ] **Control Flow** - if/for/while/match/switch
- [ ] **Functions & Decorators** - def, async, decorators
- [ ] **Imports & Modules** - Complete import system reference

#### 3.3 Language Guide: Object-Spatial Programming

- [ ] **Introduction to OSP** - Paradigm explanation (consolidate 4+ sources)
- [ ] **Nodes & Edges** - Graph primitives with examples
- [ ] **Walkers & Abilities** - Mobile computation
- [ ] **Graph Operations** - Traversal, filtering, connection operators
- [ ] **Advanced Patterns** - Multi-hop, BFS/DFS, complex queries

#### 3.4 Language Guide: Enhanced OOP

- [ ] **Objects & Classes** - obj vs class, has declarations
- [ ] **Access Control** - :pub, :priv, :protect
- [ ] **Implementation Files** - .impl.jac pattern

#### 3.5 CLI Reference (Complete Rewrite)

- [ ] **Overview** - All commands at a glance
- [ ] Individual page per command with:
  - Synopsis
  - Description
  - All options with defaults
  - Examples
  - Related commands

#### 3.6 Configuration Reference (Complete Rewrite)

- [ ] **jac.toml Complete Reference** - Every option
- [ ] **Environment Variables** - All supported env vars
- [ ] **Plugin Configuration** - Per-plugin settings
- [ ] **Environment Profiles** - Dev/prod configurations

### Deliverables

- Complete Getting Started section
- Complete Language Guide
- Complete CLI Reference
- Complete Configuration Reference

---

## Phase 4: Plugin Documentation Expansion

**Goal**: Comprehensive documentation for jac-client, jac-scale, and byLLM

### Tasks

#### 4.1 AI Integration (byLLM) - Reorganize & Expand

- [ ] **Introduction to MTP** - Meaning Typed Programming concept
- [ ] **Quick Start** - Basic examples (clean up existing)
- [ ] **The "by" Syntax** - Complete syntax reference with all parameters
- [ ] **Type-Safe Outputs** - Custom types, enums, dataclasses
- [ ] **Multimodal** - Images (Image class), Video (Video class)
- [ ] **Agentic AI & ReAct** - Tool calling, multi-step reasoning
- [ ] **MTIR Deep Dive** - NEW: Multi-Turn Interaction Runtime
- [ ] **Configuration** - jac.toml settings, environment variables
- [ ] **Python Library Mode** - Using byLLM in pure Python
- [ ] **Testing with MockLLM** - NEW: Testing without API calls
- [ ] **Examples Gallery** - Curated, working examples

#### 4.2 Full-Stack Development (jac-client) - Reorganize & Expand

- [ ] **Getting Started** - Setup, `jac create --cl`
- [ ] **Components & JSX** - React-style components
- [ ] **State Management** - useState, useEffect, hooks reference
- [ ] **Routing** - Complete routing guide with all hooks
- [ ] **Styling Guide** - All 6 methods with examples
- [ ] **Backend Integration** - spawn syntax, walkers as API
- [ ] **Authentication** - jacLogin, jacSignup, protected routes
- [ ] **Package Management** - `jac add --cl`, npm integration
- [ ] **TypeScript** - TS component integration
- [ ] **File Organization** - Project structure patterns
- [ ] **Import System** - What's implemented vs planned
- [ ] **Advanced Configuration** - Vite, custom builds

#### 4.3 Production & Scaling (jac-scale) - Major Expansion

- [ ] **Introduction** - What jac-scale provides (replace jac-cloud intro)
- [ ] **Quick Start** - `jac serve` and `jac scale`
- [ ] **Memory Architecture** - NEW: L1/L2/L3 tier explanation
- [ ] **API Generation** - How walkers become REST endpoints
- [ ] **Authentication & SSO** - JWT configuration, Google OAuth setup
- [ ] **Kubernetes Deployment** - Complete K8s guide
- [ ] **Configuration Reference** - All env vars and jac.toml options
- [ ] **Docker Deployment** - Build mode vs direct mode
- [ ] **Scaling & HPA** - Horizontal Pod Autoscaler
- [ ] **Migration from jac-cloud** - Transition guide
- [ ] **Troubleshooting** - Common issues and solutions

### Deliverables

- Complete byLLM documentation with MTIR
- Complete jac-client documentation
- Complete jac-scale documentation (replacing jac-cloud)
- All plugin configuration documented

---

## Phase 5: Advanced Topics & Testing/Debugging

**Goal**: Fill remaining gaps in advanced documentation

### Tasks

#### 5.1 Testing & Debugging Section (New)

- [ ] **Testing Framework** - Writing tests, assertions, test blocks
- [ ] **Running Tests** - `jac test` options, filtering
- [ ] **Debugging Tools** - All `jac tool ir` commands
- [ ] **Graph Visualization** - printgraph, `jac dot`
- [ ] **Troubleshooting Guide** - Common errors and solutions

#### 5.2 Advanced Topics Section (New)

- [ ] **Plugin Development** - Creating custom Jac plugins
- [ ] **Persistence Deep Dive** - Memory tiers, ShelfDB, custom backends
- [ ] **Access Control** - Multi-root, permissions system
- [ ] **Concurrency** - flow/wait syntax, async patterns
- [ ] **Performance Optimization** - Best practices
- [ ] **Python Interoperability** - Library mode deep dive

#### 5.3 Update The Jac Book

- [ ] Review all 20 chapters for accuracy
- [ ] Add cross-references to new sections
- [ ] Update code examples to current syntax
- [ ] Ensure consistency with new documentation

### Deliverables

- Complete Testing & Debugging section
- Complete Advanced Topics section
- Updated Jac Book with cross-references

---

## Phase 6: Polish, Examples & Launch

**Goal**: Final quality pass and launch preparation

### Tasks

#### 6.1 Examples Section

- [ ] Curate example categories (Beginner/Intermediate/Advanced)
- [ ] Verify all examples run correctly
- [ ] Add explanatory comments
- [ ] Create example index page

#### 6.2 Quality Assurance

- [ ] Run code example validator on all pages
- [ ] Fix any broken examples
- [ ] Run link checker
- [ ] Fix any broken links
- [ ] Spell check all content
- [ ] Grammar review

#### 6.3 Navigation & UX

- [ ] Review navigation flow
- [ ] Add "Next/Previous" page links
- [ ] Ensure consistent page structure
- [ ] Add search optimization (tags, descriptions)
- [ ] Test mobile responsiveness

#### 6.4 Final Cleanup

- [ ] Remove any remaining TODO comments
- [ ] Archive old/unused files
- [ ] Update copyright dates
- [ ] Review and update mkdocs.yml metadata

#### 6.5 Launch Preparation

- [ ] Create announcement for documentation update
- [ ] Update README links
- [ ] Notify community (Discord, etc.)
- [ ] Monitor for feedback post-launch

### Deliverables

- All examples verified working
- Zero broken links
- Polished, consistent documentation
- Launch announcement ready

---

## Dependencies Between Phases

```
Phase 0 ──────────────────────────────────────────────────────────────►
         │
         ▼
Phase 1 (Critical Fixes) ────────────────────────────────────────────►
         │
         ▼
Phase 2 (New Structure) ─────────────────────────────────────────────►
         │
         ├──────────────┬───────────────┬─────────────────┐
         ▼              ▼               ▼                 ▼
Phase 3.1-3.4     Phase 3.5-3.6    Phase 4.1-4.3    Phase 5.1-5.2
(Language)        (CLI/Config)     (Plugins)        (Advanced)
         │              │               │                 │
         └──────────────┴───────────────┴─────────────────┘
                                   │
                                   ▼
                            Phase 5.3 (Jac Book Update)
                                   │
                                   ▼
                            Phase 6 (Polish & Launch)
```

**Parallel Work Possible:**

- Phases 3.1-3.4, 3.5-3.6, 4.1-4.3, and 5.1-5.2 can run in parallel after Phase 2
- Multiple writers can work on different sections simultaneously

---

## Effort Estimates

| Phase | Effort | Parallel Tracks | Notes |
|-------|--------|-----------------|-------|
| Phase 0 | 1-2 days | 1 | Foundation work |
| Phase 1 | 3-5 days | 1-2 | Critical fixes, can partially parallelize |
| Phase 2 | 2-3 days | 1 | Restructuring, needs careful coordination |
| Phase 3 | 5-10 days | 2-3 | Major content work, parallelizable |
| Phase 4 | 7-12 days | 3 | Plugin docs, fully parallelizable |
| Phase 5 | 5-8 days | 2 | Advanced topics + Jac Book update |
| Phase 6 | 3-5 days | 2 | Polish and launch |

**Total Estimate**: 4-8 weeks depending on resources and parallelization

---

## Success Metrics

### Quantitative

- [ ] Zero broken links
- [ ] 100% of code examples compile/run
- [ ] All CLI commands documented
- [ ] All jac.toml options documented
- [ ] Redirect coverage for all old URLs

### Qualitative

- [ ] New user can go from zero to running app in < 30 minutes
- [ ] Any CLI command can be understood from docs alone
- [ ] Clear separation between learning vs reference content
- [ ] No redundant explanations of same concept
- [ ] Consistent terminology throughout

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking existing bookmarks | Comprehensive redirects in Phase 2 |
| Introducing new errors | Code validation in Phase 0, QA in Phase 6 |
| Losing content during migration | Archive in Phase 0, careful migration in Phase 2 |
| Scope creep | Strict phase boundaries, defer nice-to-haves |
| Inconsistent style | Style guide in Phase 0, review in Phase 6 |

---

## Quick Reference: Files to Create/Modify

### New Files to Create

```
docs/STYLE_GUIDE.md
docs/scripts/validate_examples.py
docs/URL_REDIRECTS.md

docs/docs/getting-started/index.md
docs/docs/getting-started/installation.md
docs/docs/getting-started/hello-world.md
docs/docs/getting-started/quickstart-osp.md
docs/docs/getting-started/ide-setup.md

docs/docs/language/syntax/index.md
docs/docs/language/syntax/python-superset.md
docs/docs/language/syntax/variables-types.md
docs/docs/language/syntax/control-flow.md
docs/docs/language/syntax/functions.md
docs/docs/language/syntax/imports.md

docs/docs/language/osp/index.md
docs/docs/language/osp/introduction.md
docs/docs/language/osp/nodes-edges.md
docs/docs/language/osp/walkers-abilities.md
docs/docs/language/osp/graph-operations.md
docs/docs/language/osp/advanced-patterns.md

docs/docs/language/oop/index.md
docs/docs/language/oop/objects-classes.md
docs/docs/language/oop/access-control.md
docs/docs/language/oop/implementation-files.md

docs/docs/cli/index.md
docs/docs/cli/run.md
docs/docs/cli/serve.md
docs/docs/cli/scale.md
docs/docs/cli/create.md
docs/docs/cli/test.md
docs/docs/cli/build.md
docs/docs/cli/check.md
docs/docs/cli/format.md
docs/docs/cli/plugins.md
docs/docs/cli/tool.md
docs/docs/cli/dot.md
docs/docs/cli/package-management.md
docs/docs/cli/other-commands.md

docs/docs/configuration/index.md
docs/docs/configuration/jac-toml-reference.md
docs/docs/configuration/environment-variables.md
docs/docs/configuration/plugin-configuration.md
docs/docs/configuration/environment-profiles.md

docs/docs/testing-debugging/index.md
docs/docs/testing-debugging/testing-framework.md
docs/docs/testing-debugging/debugging-tools.md
docs/docs/testing-debugging/graph-visualization.md
docs/docs/testing-debugging/troubleshooting.md

docs/docs/advanced/index.md
docs/docs/advanced/plugin-development.md
docs/docs/advanced/persistence.md
docs/docs/advanced/access-control.md
docs/docs/advanced/concurrency.md
docs/docs/advanced/performance.md
docs/docs/advanced/python-interop.md

docs/docs/ai-integration/index.md
docs/docs/ai-integration/mtp-introduction.md
docs/docs/ai-integration/quickstart.md
docs/docs/ai-integration/by-syntax.md
docs/docs/ai-integration/type-safe-outputs.md
docs/docs/ai-integration/multimodal.md
docs/docs/ai-integration/agentic-react.md
docs/docs/ai-integration/mtir.md
docs/docs/ai-integration/configuration.md
docs/docs/ai-integration/python-mode.md
docs/docs/ai-integration/testing-mockllm.md
docs/docs/ai-integration/examples.md

docs/docs/full-stack/index.md
docs/docs/full-stack/getting-started.md
docs/docs/full-stack/components-jsx.md
docs/docs/full-stack/state-management.md
docs/docs/full-stack/routing.md
docs/docs/full-stack/styling.md
docs/docs/full-stack/backend-integration.md
docs/docs/full-stack/authentication.md
docs/docs/full-stack/package-management.md
docs/docs/full-stack/typescript.md
docs/docs/full-stack/file-organization.md
docs/docs/full-stack/imports.md
docs/docs/full-stack/advanced-config.md

docs/docs/production/index.md
docs/docs/production/introduction.md
docs/docs/production/quickstart.md
docs/docs/production/memory-architecture.md
docs/docs/production/api-generation.md
docs/docs/production/authentication-sso.md
docs/docs/production/kubernetes.md
docs/docs/production/configuration.md
docs/docs/production/docker.md
docs/docs/production/scaling-hpa.md
docs/docs/production/migration-from-jac-cloud.md
docs/docs/production/troubleshooting.md

docs/docs/archive/jac-cloud/index.md
```

### Files to Modify

```
docs/mkdocs.yml (major restructure)
docs/docs/learn/tools/cli.md (fix errors, then archive)
docs/docs/learn/tools/project_config.md (fix errors, then migrate)
docs/docs/jac_book/*.md (update cross-references)
```

### Files to Archive/Remove

```
docs/docs/learn/jac-cloud/* → docs/docs/archive/jac-cloud/
docs/docs/learn/getting_started.md (redundant)
docs/docs/learn/beginners_guide_to_jac.md (commented out, remove)
```

---

## Next Steps

1. Review this plan with stakeholders
2. Assign resources/writers to phases
3. Create tracking issues for each phase
4. Begin Phase 0: Preparation & Foundation

---

*This plan is designed to be executed incrementally. Each phase produces working documentation, allowing for feedback and course correction throughout the process.*
