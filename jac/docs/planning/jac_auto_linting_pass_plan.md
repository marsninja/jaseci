# Jac Auto Linting Pass Implementation Plan

> **Status: IMPLEMENTED (Phase 1) / PLANNED (Phase 2)**
>
> Phase 1 (JAC001) has been implemented. See the implementation files:
>
> - Pass: `jac/jaclang/compiler/passes/tool/jac_auto_lint_pass.jac`
> - Tests: `jac/tests/compiler/passes/tool/test_jac_auto_lint_pass.py`
> - Fixtures: `jac/tests/compiler/passes/tool/fixtures/auto_lint/`
>
> Phase 2 introduces the modular rule architecture and additional rules.

## Overview

This document outlines the architecture and implementation plan for the **Jac Auto Linting Pass** - a new compiler pass that automatically detects code patterns and rewrites them to follow Jac best practices. The pass uses a **modular rule-based architecture** where each lint rule has a unique code (e.g., `JAC001`, `JAC002`) and can be individually enabled or disabled.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Modular Rule Architecture](#modular-rule-architecture)
3. [Pass Integration](#pass-integration)
4. [CLI Integration](#cli-integration)
5. [Rule JAC001: With Entry Block Simplification](#rule-jac001-with-entry-block-simplification)
6. [Rule JAC002: Init Method Conversion](#rule-jac002-init-method-conversion)
7. [Comment Handling Strategy](#comment-handling-strategy)
8. [Implementation Steps](#implementation-steps)
9. [Testing Strategy](#testing-strategy)
10. [Future Extensions](#future-extensions)

---

## Architecture Overview

### Pass Location and Structure

The auto linting pass will be placed in the `tool` passes directory alongside the existing formatting passes:

```
jac/jaclang/compiler/passes/tool/
├── __init__.py
├── doc_ir.jac
├── doc_ir_gen_pass.jac
├── comment_injection_pass.jac
├── jac_formatter_pass.jac
└── jac_auto_lint_pass.jac  # NEW
```

### Pass Design Pattern

Following the existing pass architecture, the auto linting pass will:

1. Inherit from `UniPass` (the base visitor pattern class)
2. Use `enter_*` and `exit_*` methods for node traversal
3. Perform AST transformations in-place where possible
4. Track changes for reporting purposes

```jac
"""Jac Auto Linting Pass for automatic code pattern corrections."""
import jaclang.pycore.unitree as uni;
import from jaclang.pycore.passes { UniPass }

class JacAutoLintPass(UniPass) {
    """Auto linting pass that applies code style corrections."""

    with entry {
        changes_made: list[str] = [];
        lint_enabled: bool = True;
    }

    def before_pass(self: JacAutoLintPass) -> None {
        self.changes_made = [];
    }

    def after_pass(self: JacAutoLintPass) -> None {
        # Report changes if any
        pass;
    }

    # Feature-specific methods will be added here
}
```

---

## Modular Rule Architecture

### Rule Registry Design

Each lint rule is a self-contained unit with:
- **Rule Code**: Unique identifier (e.g., `JAC001`, `JAC002`)
- **Name**: Human-readable name
- **Description**: What the rule does
- **Category**: Grouping for related rules (e.g., `style`, `modernize`, `simplify`)
- **Default State**: Whether enabled by default
- **Apply Method**: The transformation logic

### Rule Code Convention

```
JAC[XXX] - Jac-specific lint rules

Categories by number range:
  JAC001-JAC099: Code simplification rules
  JAC100-JAC199: Modernization rules (Python -> Jac idioms)
  JAC200-JAC299: Style consistency rules
  JAC300-JAC399: Import organization rules
  JAC400-JAC499: Type annotation rules
```

### Rule Registry Implementation

```jac
"""Rule registry for modular lint rule management."""

enum RuleCategory {
    SIMPLIFY,
    MODERNIZE,
    STYLE,
    IMPORTS,
    TYPES
}

obj LintRule {
    has code: str;
    has name: str;
    has description: str;
    has category: RuleCategory;
    has enabled_by_default: bool = True;

    can apply(node: uni.AstNode) -> bool;  # Returns True if changes were made
}

obj RuleRegistry {
    has rules: dict[str, LintRule] = {};
    has enabled_rules: set[str] = set();
    has disabled_rules: set[str] = set();

    can register(rule: LintRule) -> None {
        self.rules[rule.code] = rule;
        if rule.enabled_by_default {
            self.enabled_rules.add(rule.code);
        }
    }

    can enable(code: str) -> None {
        """Enable a specific rule by code."""
        if code in self.rules {
            self.enabled_rules.add(code);
            self.disabled_rules.discard(code);
        }
    }

    can disable(code: str) -> None {
        """Disable a specific rule by code."""
        if code in self.rules {
            self.disabled_rules.add(code);
            self.enabled_rules.discard(code);
        }
    }

    can enable_category(category: RuleCategory) -> None {
        """Enable all rules in a category."""
        for (code, rule) in self.rules.items() {
            if rule.category == category {
                self.enable(code);
            }
        }
    }

    can disable_category(category: RuleCategory) -> None {
        """Disable all rules in a category."""
        for (code, rule) in self.rules.items() {
            if rule.category == category {
                self.disable(code);
            }
        }
    }

    can is_enabled(code: str) -> bool {
        return code in self.enabled_rules and code not in self.disabled_rules;
    }

    can get_enabled_rules() -> list[LintRule] {
        return [rule for (code, rule) in self.rules.items() if self.is_enabled(code)];
    }
}

# Global registry instance
glob RULE_REGISTRY = RuleRegistry();
```

### Updated Pass Design with Rule Registry

```jac
"""Jac Auto Linting Pass with modular rule architecture."""
import jaclang.pycore.unitree as uni;
import from jaclang.pycore.passes { UniPass }

class JacAutoLintPass(UniPass) {
    """Auto linting pass that applies registered lint rules."""

    with entry {
        changes_made: list[tuple[str, str]] = [];  # (rule_code, description)
        registry: RuleRegistry = RULE_REGISTRY;
    }

    def before_pass(self: JacAutoLintPass) -> None {
        self.changes_made = [];
    }

    def after_pass(self: JacAutoLintPass) -> None {
        if self.changes_made {
            for (code, desc) in self.changes_made {
                # Report: "[JAC001] Extracted 3 assignments to glob"
                print(f"[{code}] {desc}");
            }
        }
    }

    def enter_module(self: JacAutoLintPass, node: uni.Module) -> None {
        for rule in self.registry.get_enabled_rules() {
            if rule.apply(node) {
                self.changes_made.append((rule.code, rule.name));
            }
        }
    }
}
```

### Rule Definitions

```jac
"""Individual rule implementations."""

obj WithEntrySimplificationRule(LintRule) {
    has code: str = "JAC001";
    has name: str = "with-entry-to-glob";
    has description: str = "Convert simple with entry assignments to glob declarations";
    has category: RuleCategory = RuleCategory.SIMPLIFY;
    has enabled_by_default: bool = True;

    can apply(node: uni.AstNode) -> bool {
        # Implementation details in Rule JAC001 section
        ...
    }
}

obj InitMethodConversionRule(LintRule) {
    has code: str = "JAC100";
    has name: str = "init-method-conversion";
    has description: str = "Convert __init__ and __post_init__ to Jac init/postinit keywords";
    has category: RuleCategory = RuleCategory.MODERNIZE;
    has enabled_by_default: bool = True;

    can apply(node: uni.AstNode) -> bool {
        # Implementation details in Rule JAC002 section
        ...
    }
}

# Register all rules
RULE_REGISTRY.register(WithEntrySimplificationRule());
RULE_REGISTRY.register(InitMethodConversionRule());
```

---

## Pass Integration

### Schedule Integration

The auto linting pass should run **before** the formatting passes but **after** parsing. This ensures:

1. The AST is valid and parsed
2. Comments are preserved in `module.source.comments`
3. The formatter can then format the linted code

Update `jac/jaclang/pycore/program.py`:

```python
def get_lint_sched() -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return auto-linting schedule with lazy imports."""
    from jaclang.compiler.passes.tool.jac_auto_lint_pass import JacAutoLintPass
    return [JacAutoLintPass]

def get_format_sched() -> list[type[Transform[uni.Module, uni.Module]]]:
    """Return format schedule with lazy imports to allow doc_ir.jac conversion."""
    from jaclang.compiler.passes.tool.jac_auto_lint_pass import JacAutoLintPass
    from jaclang.compiler.passes.tool.comment_injection_pass import CommentInjectionPass
    from jaclang.compiler.passes.tool.doc_ir_gen_pass import DocIRGenPass
    from jaclang.compiler.passes.tool.jac_formatter_pass import JacFormatPass

    return [
        JacAutoLintPass,      # NEW - runs first
        DocIRGenPass,
        CommentInjectionPass,
        JacFormatPass,
    ]
```

### Module Registration

Add to `jac/jaclang/compiler/passes/tool/__init__.py`:

```python
"""Tool passes for Jac formatting, documentation, and linting."""
```

---

## CLI Integration

### Format Command Enhancement

Modify the `format` command in `jac/jaclang/cli/cli.jac` to support rule selection:

```jac
"""Format .jac files with improved code style.

Applies consistent formatting to Jac code files and optionally applies
automatic linting corrections (on by default).

Args:
    paths: One or more paths to .jac files or directories
    outfile: Optional output file path (single file only)
    to_screen: Print formatted code to stdout
    lint: Apply auto-linting corrections (default: True)
    enable_rules: Comma-separated list of rule codes to enable (e.g., "JAC001,JAC100")
    disable_rules: Comma-separated list of rule codes to disable
    list_rules: List all available lint rules and exit

Examples:
    jac format myfile.jac
    jac format myfile.jac --no-lint
    jac format myfile.jac --enable-rules JAC001,JAC100
    jac format myfile.jac --disable-rules JAC100
    jac format --list-rules
"""
@cmd_registry.register
def format(
    paths: list,
    outfile: str = '',
    to_screen: bool = False,
    lint: bool = True,
    enable_rules: str = '',   # NEW - comma-separated rule codes
    disable_rules: str = '',  # NEW - comma-separated rule codes
    list_rules: bool = False  # NEW - show available rules
) -> None {
    # Handle --list-rules
    if list_rules {
        print("Available lint rules:");
        print("-" * 60);
        for (code, rule) in sorted(RULE_REGISTRY.rules.items()) {
            status = "[ON] " if rule.enabled_by_default else "[OFF]";
            print(f"  {status} {code}: {rule.name}");
            print(f"         {rule.description}");
        }
        return;
    }

    # Configure rule registry based on flags
    if enable_rules {
        for code in enable_rules.split(",") {
            RULE_REGISTRY.enable(code.strip());
        }
    }
    if disable_rules {
        for code in disable_rules.split(",") {
            RULE_REGISTRY.disable(code.strip());
        }
    }

    # ... existing validation code ...

    def format_single_file(file_path: str) -> tuple[bool, bool] {
        # Modified to pass lint flag
        prog = JacProgram.jac_file_formatter(str(path_obj), auto_lint=lint);
        # ... rest of implementation
    }
}
```

### Rule Selection Examples

```bash
# Format with all default rules
jac format myfile.jac

# Format without any linting
jac format myfile.jac --no-lint

# Format with only specific rules enabled
jac format myfile.jac --enable-rules JAC001

# Format with specific rules disabled
jac format myfile.jac --disable-rules JAC100

# Combine enable and disable
jac format myfile.jac --enable-rules JAC001,JAC100 --disable-rules JAC200

# List all available rules
jac format --list-rules
```

### Expected Output from --list-rules

```
Available lint rules:
------------------------------------------------------------
  [ON]  JAC001: with-entry-to-glob
         Convert simple with entry assignments to glob declarations
  [ON]  JAC100: init-method-conversion
         Convert __init__ and __post_init__ to Jac init/postinit keywords
  [OFF] JAC200: string-quote-style
         Enforce consistent string quote style
  ...
```

### Program Method Update

Update `jac/jaclang/pycore/program.py`:

```python
@staticmethod
def jac_file_formatter(file_path: str, auto_lint: bool = True) -> JacProgram:
    """Format a Jac file and return the JacProgram."""
    prog = JacProgram()
    source_str = read_file_with_encoding(file_path)
    source = uni.Source(source_str, mod_path=file_path)
    parser_pass = JacParser(root_ir=source, prog=prog)
    current_mod = parser_pass.ir_out

    # Conditionally include linting
    schedule = get_format_sched() if auto_lint else get_format_sched_no_lint()

    for pass_cls in schedule:
        current_mod = pass_cls(ir_in=current_mod, prog=prog).ir_out
    prog.mod = uni.ProgramModule(current_mod)
    return prog
```

---

## Rule JAC001: With Entry Block Simplification

| Property | Value |
|----------|-------|
| **Code** | `JAC001` |
| **Name** | `with-entry-to-glob` |
| **Category** | `SIMPLIFY` |
| **Default** | Enabled |

### Problem Statement

`with entry` blocks are often used unnecessarily for simple assignments that could be module-level `glob` declarations:

**Before (unnecessary with entry):**

```jac
with entry {
    x = 5;
    y = "hello";
    z = [1, 2, 3];
}
```

**After (using glob):**

```jac
glob x = 5;
glob y = "hello";
glob z = [1, 2, 3];
```

### AST Transformation Rules

#### Rule 1: Simple Assignment Extraction

**Condition:** An assignment in a `with entry` block where:

- The target is a simple name (not attribute access, subscript, etc.)
- The value is a pure expression (literal, list, dict, arithmetic on literals)
- No side effects (no function calls that might have side effects)

**Transform:** Convert to `glob` statement at module level

#### Rule 2: Entry Block Removal

**Condition:** After extraction, if `with entry` block is:

- Empty
- Contains only semicolons/empty statements

**Transform:** Remove the entire `with entry` block

#### Rule 3: Partial Extraction

**Condition:** `with entry` block contains both extractable and non-extractable statements

**Transform:**

- Extract only the extractable assignments to `glob`
- Keep non-extractable statements in `with entry`

### Implementation Details

#### Key AST Node Types (from `unitree.py`)

```python
# Module level with entry block
class ModuleCode(ClientFacingNode, ElementStmt, ArchBlockStmt, EnumBlockStmt):
    name: Name | None  # None for unnamed entry blocks
    body: Sequence[CodeBlockStmt]

# Global variable declaration
class GlobalVars(ClientFacingNode, ElementStmt, AstAccessNode):
    access: SubTag[Token] | None
    assignments: Sequence[Assignment]
    is_frozen: bool

# Assignment statement
class Assignment(AstTypedVarNode, EnumBlockStmt, CodeBlockStmt):
    target: list[Expr]
    value: Expr | YieldExpr | None
    type_tag: SubTag[Expr] | None
    mutable: bool = True
    aug_op: Token | None
```

#### Extraction Logic

```jac
"""Check if an assignment can be extracted to glob."""
def can_extract_to_glob(self: JacAutoLintPass, assignment: uni.Assignment) -> bool {
    # Must have a value (not just declaration)
    if assignment.value is None {
        return False;
    }

    # Target must be simple names only
    for target in assignment.target {
        if not isinstance(target, uni.Name) {
            return False;
        }
    }

    # Value must be a pure expression
    return self.is_pure_expression(assignment.value);
}

"""Check if an expression has no side effects."""
def is_pure_expression(self: JacAutoLintPass, expr: uni.Expr) -> bool {
    match expr {
        case uni.Int | uni.Float | uni.String | uni.Bool | uni.Null => {
            return True;
        }
        case uni.ListVal => {
            return all(self.is_pure_expression(e) for e in expr.values);
        }
        case uni.DictVal => {
            return all(
                self.is_pure_expression(k) and self.is_pure_expression(v)
                for (k, v) in zip(expr.keys, expr.values)
            );
        }
        case uni.SetVal | uni.TupleVal => {
            return all(self.is_pure_expression(e) for e in expr.values);
        }
        case uni.BinaryExpr => {
            return (
                self.is_pure_expression(expr.left) and
                self.is_pure_expression(expr.right)
            );
        }
        case uni.UnaryExpr => {
            return self.is_pure_expression(expr.operand);
        }
        case uni.Name => {
            # Variable references are pure (reading doesn't cause side effects)
            return True;
        }
        case _ => {
            # Function calls, attribute access, etc. - not pure
            return False;
        }
    }
}
```

#### Module Transformation

```jac
"""Process module to extract with entry assignments."""
def enter_module(self: JacAutoLintPass, node: uni.Module) -> None {
    new_body: list[uni.ElementStmt] = [];

    for stmt in node.body {
        if isinstance(stmt, uni.ModuleCode) and stmt.name is None {
            # This is an unnamed with entry block
            (glob_stmts, remaining) = self.process_entry_block(stmt);

            # Add extracted glob statements
            new_body.extend(glob_stmts);

            # Keep remaining entry block if non-empty
            if remaining.body {
                new_body.append(remaining);
            }
        } else {
            new_body.append(stmt);
        }
    }

    # Update module body
    node.body = new_body;
    self.recalculate_parents(node);
}
```

---

## Rule JAC100: Init Method Conversion

| Property | Value |
|----------|-------|
| **Code** | `JAC100` |
| **Name** | `init-method-conversion` |
| **Category** | `MODERNIZE` |
| **Default** | Enabled |

### Problem Statement

When migrating Python code to Jac or writing Jac with Python habits, developers often use `__init__` and `__post_init__` methods instead of Jac's native `init` and `postinit` keywords. This rule automatically converts these Python-style methods to idiomatic Jac syntax.

**Before (Python-style):**

```jac
obj User {
    has name: str;
    has email: str;
    has created_at: datetime;

    def __init__(self: User, name: str, email: str) -> None {
        self.name = name;
        self.email = email;
    }

    def __post_init__(self: User) -> None {
        self.created_at = datetime.now();
    }
}
```

**After (Jac-style):**

```jac
obj User {
    has name: str;
    has email: str;
    has created_at: datetime;

    can init(name: str, email: str) {
        self.name = name;
        self.email = email;
    }

    can postinit {
        self.created_at = datetime.now();
    }
}
```

### AST Transformation Rules

#### Rule 1: `__init__` to `init`

**Condition:** A method in an `obj`, `node`, `edge`, or `walker` where:
- Method name is `__init__`
- Has `self` as first parameter

**Transform:**
- Change method kind from `def` to `can`
- Rename from `__init__` to `init`
- Remove `self` parameter (implicit in Jac)
- Remove return type annotation (always None for init)

#### Rule 2: `__post_init__` to `postinit`

**Condition:** A method in an `obj`, `node`, `edge`, or `walker` where:
- Method name is `__post_init__`
- Has only `self` parameter (no additional params)

**Transform:**
- Change method kind from `def` to `can`
- Rename from `__post_init__` to `postinit`
- Remove `self` parameter (implicit in Jac)
- Remove return type annotation
- Remove parameter list entirely (postinit takes no params)

### Implementation Details

#### Key AST Node Types

```python
# Ability (method) in architype
class Ability(ClientFacingNode, ArchBlockStmt):
    name: Name
    signature: FuncSignature | EventSignature | None
    body: Sequence[CodeBlockStmt] | None
    decorators: Sequence[Expr]

# Function signature
class FuncSignature(ClientFacingNode, AstNode):
    params: Sequence[ParamVar] | None
    return_type: SubTag[Expr] | None

# Parameter variable
class ParamVar(AstTypedVarNode, AstNode):
    name: Name
    type_tag: SubTag[Expr] | None
    value: Expr | None
```

#### Detection Logic

```jac
"""Check if a method is __init__ that should be converted."""
def is_python_init(self: InitMethodConversionRule, ability: uni.Ability) -> bool {
    if ability.name.value != "__init__" {
        return False;
    }

    # Must have at least self parameter
    if ability.signature is None or ability.signature.params is None {
        return False;
    }

    # First param should be self
    if len(ability.signature.params) < 1 {
        return False;
    }

    first_param = ability.signature.params[0];
    return first_param.name.value == "self";
}

"""Check if a method is __post_init__ that should be converted."""
def is_python_post_init(self: InitMethodConversionRule, ability: uni.Ability) -> bool {
    if ability.name.value != "__post_init__" {
        return False;
    }

    # Must have signature with only self parameter
    if ability.signature is None or ability.signature.params is None {
        return False;
    }

    # Should have exactly one param (self)
    if len(ability.signature.params) != 1 {
        return False;
    }

    first_param = ability.signature.params[0];
    return first_param.name.value == "self";
}
```

#### Transformation Logic

```jac
"""Convert __init__ method to Jac init ability."""
def convert_init_method(self: InitMethodConversionRule, ability: uni.Ability) -> uni.Ability {
    # Create new name token
    new_name = self.create_name_token("init", ability.name);

    # Create new params without self
    new_params = ability.signature.params[1:];  # Skip self

    # Create new signature without return type
    new_signature = uni.FuncSignature(
        params=new_params if new_params else None,
        return_type=None,
        # Copy other relevant fields
    );

    # Create new ability with can keyword instead of def
    return uni.Ability(
        name=new_name,
        signature=new_signature,
        body=ability.body,
        decorators=ability.decorators,
        # Mark as native Jac ability
    );
}

"""Convert __post_init__ method to Jac postinit ability."""
def convert_post_init_method(self: InitMethodConversionRule, ability: uni.Ability) -> uni.Ability {
    # Create new name token
    new_name = self.create_name_token("postinit", ability.name);

    # postinit has no signature (no params, no return type)
    return uni.Ability(
        name=new_name,
        signature=None,  # No signature for postinit
        body=ability.body,
        decorators=ability.decorators,
    );
}
```

#### Architype Visitor

```jac
"""Process architype to convert init methods."""
def enter_architype(self: InitMethodConversionRule, node: uni.Architype) -> None {
    if node.body is None {
        return;
    }

    new_body: list[uni.ArchBlockStmt] = [];
    changes_made = False;

    for stmt in node.body {
        if isinstance(stmt, uni.Ability) {
            if self.is_python_init(stmt) {
                new_stmt = self.convert_init_method(stmt);
                new_body.append(new_stmt);
                changes_made = True;
                self.record_change(f"Converted __init__ to init in {node.name.value}");
            } elif self.is_python_post_init(stmt) {
                new_stmt = self.convert_post_init_method(stmt);
                new_body.append(new_stmt);
                changes_made = True;
                self.record_change(f"Converted __post_init__ to postinit in {node.name.value}");
            } else {
                new_body.append(stmt);
            }
        } else {
            new_body.append(stmt);
        }
    }

    if changes_made {
        node.body = new_body;
        self.recalculate_parents(node);
    }
}
```

### Edge Cases

1. **Custom `__init__` with decorators**: Preserve decorators in conversion
2. **`__init__` with `*args` or `**kwargs`**: Convert but preserve variadic params
3. **`__post_init__` with params**: This is non-standard; warn but don't convert
4. **Multiple inheritance init chains**: Only convert the method definition, super() calls remain
5. **Class methods vs instance methods**: Only convert instance methods (those with self)

### Test Cases

```jac
# Test: Simple __init__ conversion
obj SimpleInit {
    has value: int;

    def __init__(self: SimpleInit, value: int) -> None {
        self.value = value;
    }
}
# Expected: can init(value: int) { self.value = value; }

# Test: __post_init__ conversion
obj WithPostInit {
    has computed: str;

    def __post_init__(self: WithPostInit) -> None {
        self.computed = "done";
    }
}
# Expected: can postinit { self.computed = "done"; }

# Test: Combined init and postinit
obj Combined {
    has x: int;
    has y: int;

    def __init__(self: Combined, x: int) -> None {
        self.x = x;
    }

    def __post_init__(self: Combined) -> None {
        self.y = self.x * 2;
    }
}
# Expected: Both converted to can init(x: int) and can postinit

# Test: Init with variadic params
obj VariadicInit {
    has args: tuple;
    has kwargs: dict;

    def __init__(self: VariadicInit, *args: any, **kwargs: any) -> None {
        self.args = args;
        self.kwargs = kwargs;
    }
}
# Expected: can init(*args: any, **kwargs: any) { ... }

# Test: Do NOT convert regular methods named similarly
obj NotConverted {
    def initialize(self: NotConverted) -> None {
        pass;
    }

    def __str__(self: NotConverted) -> str {
        return "NotConverted";
    }
}
# Expected: No changes
```

---

## Comment Handling Strategy

Comments in Jac are stored separately from the AST in `module.source.comments`. This is crucial for the auto linting pass because we need to:

1. **Preserve comments** when moving code
2. **Reattach comments** to their logical new positions
3. **Handle inline comments** that belong to specific lines

### Comment Structure (from `unitree.py`)

```python
class CommentToken(Token):
    is_inline: bool = False  # True if on same line as preceding token

class Source(EmptyToken):
    comments: list[CommentToken] = []  # All comments in source
```

### Comment Preservation Strategy

#### Step 1: Map Comments to AST Nodes

Before transformation, build a mapping of comments to their associated AST nodes:

```jac
"""Build comment-to-node mapping before transformation."""
def build_comment_map(self: JacAutoLintPass, module: uni.Module) -> dict {
    comment_map: dict[int, list[uni.CommentToken]] = {};

    for comment in module.source.comments {
        # Find the nearest AST node by line number
        node_id = self.find_owning_node(comment, module);
        if node_id not in comment_map {
            comment_map[node_id] = [];
        }
        comment_map[node_id].append(comment);
    }

    return comment_map;
}
```

#### Step 2: Transfer Comments During Extraction

When extracting an assignment to `glob`:

```jac
"""Extract assignment with its associated comments."""
def extract_with_comments(
    self: JacAutoLintPass,
    assignment: uni.Assignment,
    comment_map: dict
) -> uni.GlobalVars {
    # Get comments associated with this assignment
    comments = comment_map.get(id(assignment), []);

    # Create new GlobalVars node
    glob_stmt = self.create_glob_from_assignment(assignment);

    # Transfer comments - adjust line numbers for new position
    # Comments will be re-associated during comment injection pass

    return glob_stmt;
}
```

#### Step 3: Rely on Comment Injection Pass

The `CommentInjectionPass` already handles attaching comments to DocIR nodes based on token positions. Our strategy:

1. **Preserve original token positions** in extracted nodes when possible
2. **Update the `Source.comments` list** to reflect moved code
3. **Let CommentInjectionPass** handle final comment placement during formatting

### Edge Cases

1. **Block-level comments**: Comments before a `with entry` block should stay with the first extracted statement
2. **Inline comments**: `x = 5;  // comment` - the comment should stay on the same line as the glob
3. **Trailing comments**: Comments after all statements in `with entry` should stay after the last extracted glob
4. **Empty block comments**: If we remove an empty `with entry`, preserve any comments as standalone

---

## Implementation Steps

### Phase 1: Core Infrastructure ✅ (COMPLETED)

1. **Create pass file structure** ✅
   - Create `jac/jaclang/compiler/passes/tool/jac_auto_lint_pass.jac`
   - Add basic class skeleton inheriting from `UniPass`
   - Register in `__init__.py`

2. **Update format schedule** ✅
   - Modify `get_format_sched()` in `program.py`
   - Add `get_lint_sched()` function

3. **Add CLI flag** ✅
   - Add `--lint/--no-lint` flag to format command
   - Default to `--lint` (on)

### Phase 2: JAC001 - With Entry Extraction ✅ (COMPLETED)

1. **Implement pure expression detection** ✅
   - Create `is_pure_expression()` method
   - Handle all literal types, collections, and safe operations

2. **Implement assignment extraction check** ✅
   - Create `can_extract_to_glob()` method
   - Check target types and value purity

3. **Implement module transformation** ✅
   - Process `ModuleCode` nodes
   - Create `GlobalVars` nodes from extractable assignments
   - Update module body

4. **Implement AST node creation** ✅
   - Create proper `GlobalVars` nodes with correct token structure
   - Ensure `normalize()` produces valid output

### Phase 3: Modular Rule Architecture Refactor (Priority: High)

1. **Create Rule Registry Infrastructure**
   - Create `jac/jaclang/compiler/passes/tool/lint_rules/` directory
   - Create `__init__.py` with `RuleRegistry` class
   - Create `base_rule.jac` with `LintRule` base class
   - Define `RuleCategory` enum

2. **Refactor JAC001 as Modular Rule**
   - Move JAC001 logic to `lint_rules/jac001_with_entry_to_glob.jac`
   - Implement `LintRule` interface
   - Register with `RULE_REGISTRY`
   - Update pass to use registry

3. **Update CLI for Rule Selection**
   - Add `--enable-rules` parameter
   - Add `--disable-rules` parameter
   - Add `--list-rules` command
   - Update help text

4. **Add Configuration File Support** (Optional)
   - Support `.jaclint` or `jaclint.toml` config files
   - Allow per-project rule configuration
   - Support rule-specific options

### Phase 4: JAC100 - Init Method Conversion (Priority: High)

1. **Create JAC100 Rule File**
   - Create `lint_rules/jac100_init_conversion.jac`
   - Implement `LintRule` interface

2. **Implement Detection Logic**
   - Create `is_python_init()` method
   - Create `is_python_post_init()` method
   - Handle edge cases (decorators, variadic params)

3. **Implement Transformation Logic**
   - Create `convert_init_method()` method
   - Create `convert_post_init_method()` method
   - Handle signature transformation
   - Preserve body and decorators

4. **Implement Architype Visitor**
   - Process `obj`, `node`, `edge`, `walker` types
   - Transform matching methods
   - Update parent references

### Phase 5: Comment Handling (Priority: High)

1. **Implement comment mapping**
   - Build pre-transformation comment-to-node map
   - Track line number relationships

2. **Implement comment transfer**
   - Move comments with extracted code
   - Handle edge cases (block, inline, trailing)

3. **Test with CommentInjectionPass**
    - Verify comments appear correctly after formatting
    - Fix any position calculation issues

### Phase 6: Testing and Polish (Priority: Medium)

1. **Create test fixtures for JAC001**
    - Simple extraction cases
    - Mixed extractable/non-extractable
    - Comment preservation cases
    - Edge cases (nested, complex expressions)

2. **Create test fixtures for JAC100**
    - Simple `__init__` conversion
    - `__post_init__` conversion
    - Combined init and postinit
    - Variadic parameters
    - Decorators preservation
    - Non-matching methods (no changes)

3. **Add rule selection tests**
    - Test `--enable-rules` flag
    - Test `--disable-rules` flag
    - Test `--list-rules` output
    - Test rule combination scenarios

4. **Add integration tests**
    - Format command with lint on/off
    - Verify AST equivalence
    - Verify formatted output

5. **Documentation**
    - Update CLI help text
    - Add examples to user documentation
    - Document each rule with examples

---

## Testing Strategy

### Unit Tests

Location: `jac/tests/compiler/passes/tool/test_jac_auto_lint_pass.py`

```python
class TestJacAutoLintPass:
    """Tests for the auto-linting pass infrastructure."""

    def test_rule_registry_enable_disable(self):
        """Test rule registry enable/disable functionality."""
        registry = RuleRegistry()
        registry.register(MockRule("JAC001", enabled_by_default=True))
        registry.register(MockRule("JAC100", enabled_by_default=True))

        assert registry.is_enabled("JAC001")
        registry.disable("JAC001")
        assert not registry.is_enabled("JAC001")
        registry.enable("JAC001")
        assert registry.is_enabled("JAC001")

    def test_rule_registry_category_operations(self):
        """Test enabling/disabling rules by category."""
        registry = RuleRegistry()
        registry.register(MockRule("JAC001", category=RuleCategory.SIMPLIFY))
        registry.register(MockRule("JAC100", category=RuleCategory.MODERNIZE))

        registry.disable_category(RuleCategory.SIMPLIFY)
        assert not registry.is_enabled("JAC001")
        assert registry.is_enabled("JAC100")


class TestJAC001WithEntryToGlob:
    """Tests for JAC001: with entry to glob conversion."""

    def test_simple_assignment_extraction(self):
        """Test extracting simple assignments from with entry."""
        code = '''
        with entry {
            x = 5;
        }
        '''
        expected = 'glob x = 5;'
        # ...

    def test_mixed_extraction(self):
        """Test partial extraction when some statements can't be extracted."""
        code = '''
        with entry {
            x = 5;
            print("hello");  // Can't extract
        }
        '''
        # Verify x is extracted, print stays in with entry

    def test_comment_preservation(self):
        """Test that comments are preserved during extraction."""
        code = '''
        // Header comment
        with entry {
            x = 5;  // inline
        }
        '''
        # Verify comments appear in output


class TestJAC100InitConversion:
    """Tests for JAC100: __init__ and __post_init__ conversion."""

    def test_simple_init_conversion(self):
        """Test converting simple __init__ to init."""
        code = '''
        obj Foo {
            has x: int;

            def __init__(self: Foo, x: int) -> None {
                self.x = x;
            }
        }
        '''
        expected = '''
        obj Foo {
            has x: int;

            can init(x: int) {
                self.x = x;
            }
        }
        '''
        # ...

    def test_post_init_conversion(self):
        """Test converting __post_init__ to postinit."""
        code = '''
        obj Bar {
            has computed: str;

            def __post_init__(self: Bar) -> None {
                self.computed = "done";
            }
        }
        '''
        expected = '''
        obj Bar {
            has computed: str;

            can postinit {
                self.computed = "done";
            }
        }
        '''
        # ...

    def test_init_with_multiple_params(self):
        """Test converting __init__ with multiple parameters."""
        code = '''
        obj User {
            has name: str;
            has age: int;

            def __init__(self: User, name: str, age: int = 0) -> None {
                self.name = name;
                self.age = age;
            }
        }
        '''
        # Verify params (minus self) are preserved with defaults

    def test_init_with_variadic_params(self):
        """Test converting __init__ with *args and **kwargs."""
        code = '''
        obj Flexible {
            def __init__(self: Flexible, *args: any, **kwargs: any) -> None {
                pass;
            }
        }
        '''
        # Verify variadic params are preserved

    def test_preserves_decorators(self):
        """Test that decorators are preserved during conversion."""
        code = '''
        obj Decorated {
            @some_decorator
            def __init__(self: Decorated) -> None {
                pass;
            }
        }
        '''
        # Verify decorator is preserved on converted init

    def test_no_conversion_for_non_init_methods(self):
        """Test that regular methods are not converted."""
        code = '''
        obj Normal {
            def __str__(self: Normal) -> str {
                return "Normal";
            }

            def initialize(self: Normal) -> None {
                pass;
            }
        }
        '''
        # Verify no changes to __str__ or initialize

    def test_works_on_all_architypes(self):
        """Test conversion works on obj, node, edge, walker."""
        for archtype in ['obj', 'node', 'edge', 'walker']:
            code = f'''
            {archtype} Test {{
                def __init__(self: Test) -> None {{
                    pass;
                }}
            }}
            '''
            # Verify conversion happens for each architype
```

### Fixture Files

Location: `jac/tests/compiler/passes/tool/fixtures/auto_lint/`

```
auto_lint/
├── jac001/
│   ├── simple_extraction.jac
│   ├── simple_extraction.expected.jac
│   ├── mixed_statements.jac
│   ├── mixed_statements.expected.jac
│   ├── with_comments.jac
│   ├── with_comments.expected.jac
│   ├── no_extraction_needed.jac
│   ├── complex_values.jac
│   └── nested_entry.jac
├── jac100/
│   ├── simple_init.jac
│   ├── simple_init.expected.jac
│   ├── post_init.jac
│   ├── post_init.expected.jac
│   ├── combined_init.jac
│   ├── combined_init.expected.jac
│   ├── variadic_params.jac
│   ├── variadic_params.expected.jac
│   ├── with_decorators.jac
│   ├── with_decorators.expected.jac
│   ├── all_architypes.jac
│   ├── all_architypes.expected.jac
│   └── no_conversion.jac
└── rule_selection/
    ├── both_rules_enabled.jac
    ├── both_rules_enabled.expected.jac
    ├── jac001_only.jac
    ├── jac001_only.expected.jac
    ├── jac100_only.jac
    └── jac100_only.expected.jac
```

### Integration Tests

```python
class TestCLIRuleSelection:
    """Tests for CLI rule selection functionality."""

    def test_format_with_lint(self):
        """Test format command applies linting by default."""
        result = run_cli(['jac', 'format', 'test.jac', '--to_screen'])
        assert 'glob' in result.stdout

    def test_format_without_lint(self):
        """Test format command with --no-lint preserves with entry."""
        result = run_cli(['jac', 'format', 'test.jac', '--to_screen', '--no-lint'])
        assert 'with entry' in result.stdout

    def test_enable_specific_rules(self):
        """Test --enable-rules flag enables only specified rules."""
        result = run_cli([
            'jac', 'format', 'test.jac', '--to_screen',
            '--enable-rules', 'JAC001'
        ])
        # Verify JAC001 applied, JAC100 not applied

    def test_disable_specific_rules(self):
        """Test --disable-rules flag disables specified rules."""
        result = run_cli([
            'jac', 'format', 'test.jac', '--to_screen',
            '--disable-rules', 'JAC100'
        ])
        # Verify JAC001 applied, JAC100 not applied

    def test_list_rules(self):
        """Test --list-rules shows all available rules."""
        result = run_cli(['jac', 'format', '--list-rules'])
        assert 'JAC001' in result.stdout
        assert 'JAC100' in result.stdout
        assert 'with-entry-to-glob' in result.stdout
        assert 'init-method-conversion' in result.stdout

    def test_combine_enable_disable(self):
        """Test combining --enable-rules and --disable-rules."""
        result = run_cli([
            'jac', 'format', 'test.jac', '--to_screen',
            '--enable-rules', 'JAC001,JAC100',
            '--disable-rules', 'JAC001'
        ])
        # Verify only JAC100 applied (disable takes precedence)
```

---

## Future Extensions

The modular rule architecture makes adding new lint rules straightforward. Each rule is self-contained with its own code, tests, and documentation.

### Rule Reference Table

| Code | Name | Category | Default | Description |
|------|------|----------|---------|-------------|
| `JAC001` | `with-entry-to-glob` | SIMPLIFY | ON | Convert simple with entry assignments to glob declarations |
| `JAC100` | `init-method-conversion` | MODERNIZE | ON | Convert `__init__`/`__post_init__` to Jac `init`/`postinit` |
| `JAC200` | `string-quote-style` | STYLE | OFF | Enforce consistent string quote style |
| `JAC300` | `import-organization` | IMPORTS | OFF | Sort and group imports |
| `JAC301` | `unused-import-removal` | IMPORTS | OFF | Remove unused imports |
| `JAC400` | `infer-type-annotations` | TYPES | OFF | Add type hints where inferable |

### Planned Rules

#### SIMPLIFY Category (JAC001-JAC099)

| Code | Name | Description |
|------|------|-------------|
| `JAC002` | `empty-block-removal` | Remove empty `with entry` blocks |
| `JAC003` | `redundant-pass-removal` | Remove unnecessary `pass` statements |
| `JAC004` | `simplify-boolean-expr` | Simplify redundant boolean expressions |

#### MODERNIZE Category (JAC100-JAC199)

| Code | Name | Description |
|------|------|-------------|
| `JAC100` | `init-method-conversion` | **IMPLEMENTED** - Convert `__init__`/`__post_init__` |
| `JAC101` | `dunder-to-ability` | Convert other dunder methods to Jac abilities |
| `JAC102` | `class-to-obj` | Convert Python-style `class` to Jac `obj` |
| `JAC103` | `property-to-has` | Convert `@property` to `has` with getters |

#### STYLE Category (JAC200-JAC299)

| Code | Name | Description |
|------|------|-------------|
| `JAC200` | `string-quote-style` | Enforce consistent quote style (single/double) |
| `JAC201` | `naming-conventions` | Enforce Jac naming conventions |
| `JAC202` | `trailing-semicolons` | Ensure consistent semicolon usage |

#### IMPORTS Category (JAC300-JAC399)

| Code | Name | Description |
|------|------|-------------|
| `JAC300` | `import-organization` | Sort imports alphabetically, group by type |
| `JAC301` | `unused-import-removal` | Remove unused imports (with warning) |
| `JAC302` | `import-deduplication` | Remove duplicate imports |

#### TYPES Category (JAC400-JAC499)

| Code | Name | Description |
|------|------|-------------|
| `JAC400` | `infer-type-annotations` | Add type hints where inferable |
| `JAC401` | `return-type-inference` | Suggest return types for functions |
| `JAC402` | `any-type-warnings` | Warn about explicit `any` types |

### Adding New Lint Rules

To add a new lint rule:

1. **Create Rule File**
   ```
   jac/jaclang/compiler/passes/tool/lint_rules/jacXXX_rule_name.jac
   ```

2. **Implement LintRule Interface**
   ```jac
   obj MyNewRule(LintRule) {
       has code: str = "JACXXX";
       has name: str = "rule-name";
       has description: str = "What this rule does";
       has category: RuleCategory = RuleCategory.CATEGORY;
       has enabled_by_default: bool = False;  # Start disabled for new rules

       can apply(node: uni.AstNode) -> bool {
           # Return True if changes were made
           ...
       }
   }
   ```

3. **Register the Rule**
   ```jac
   # In lint_rules/__init__.py or auto-discovery
   RULE_REGISTRY.register(MyNewRule());
   ```

4. **Add Tests**
   - Create fixtures in `fixtures/auto_lint/jacXXX/`
   - Add unit tests in `test_jac_auto_lint_pass.py`

5. **Document the Rule**
   - Add to Rule Reference Table above
   - Include before/after examples
   - Document edge cases

### Configuration File Support (Future)

Support for `.jaclint.toml` configuration:

```toml
# .jaclint.toml
[rules]
# Enable all rules by default
default = "enable"

# Disable specific rules
disable = ["JAC200", "JAC201"]

# Rule-specific options
[rules.JAC200]
quote_style = "double"

[rules.JAC300]
import_order = ["stdlib", "third_party", "local"]
```

---

## Summary

This implementation plan provides a clean, extensible architecture for the Jac Auto Linting Pass with careful attention to:

1. **Modular Design**: Each rule is self-contained with unique codes (JAC001, JAC100, etc.)
2. **Selective Application**: Users can enable/disable rules via CLI flags
3. **Integration**: Fits naturally into the existing pass system
4. **CLI Experience**: On by default with granular control via `--enable-rules`/`--disable-rules`
5. **Comment Preservation**: Leverages existing comment handling infrastructure
6. **Extensibility**: Simple interface for adding new lint rules
7. **Testing**: Comprehensive test strategy with per-rule fixtures

### Current Rules

| Code | Status | Description |
|------|--------|-------------|
| `JAC001` | ✅ Implemented | With entry to glob conversion |
| `JAC100` | 📋 Planned | Init method conversion |

The modular architecture ensures that new rules can be added independently without affecting existing functionality, and users have fine-grained control over which transformations are applied to their code.
