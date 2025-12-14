# Jac Auto Linting Pass Implementation Plan

## Overview

This document outlines the architecture and implementation plan for the **Jac Auto Linting Pass** - a new compiler pass that automatically detects code patterns and rewrites them to follow Jac best practices. The first feature will focus on simplifying `with entry` blocks by extracting assignments to module-level `glob` declarations.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Pass Integration](#pass-integration)
3. [CLI Integration](#cli-integration)
4. [First Feature: With Entry Block Simplification](#first-feature-with-entry-block-simplification)
5. [Comment Handling Strategy](#comment-handling-strategy)
6. [Implementation Steps](#implementation-steps)
7. [Testing Strategy](#testing-strategy)
8. [Future Extensions](#future-extensions)

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

Modify the `format` command in `jac/jaclang/cli/cli.jac` to support a `--no-lint` flag:

```jac
"""Format .jac files with improved code style.

Applies consistent formatting to Jac code files and optionally applies
automatic linting corrections (on by default).

Args:
    paths: One or more paths to .jac files or directories
    outfile: Optional output file path (single file only)
    to_screen: Print formatted code to stdout
    lint: Apply auto-linting corrections (default: True)

Examples:
    jac format myfile.jac
    jac format myfile.jac --no-lint
"""
@cmd_registry.register
def format(
    paths: list,
    outfile: str = '',
    to_screen: bool = False,
    lint: bool = True  # NEW - on by default
) -> None {
    # ... existing validation code ...

    def format_single_file(file_path: str) -> tuple[bool, bool] {
        # Modified to pass lint flag
        prog = JacProgram.jac_file_formatter(str(path_obj), auto_lint=lint);
        # ... rest of implementation
    }
}
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

## First Feature: With Entry Block Simplification

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

### Phase 1: Core Infrastructure (Priority: High)

1. **Create pass file structure**
   - Create `jac/jaclang/compiler/passes/tool/jac_auto_lint_pass.jac`
   - Add basic class skeleton inheriting from `UniPass`
   - Register in `__init__.py`

2. **Update format schedule**
   - Modify `get_format_sched()` in `program.py`
   - Add `get_lint_sched()` function

3. **Add CLI flag**
   - Add `--lint/--no-lint` flag to format command
   - Default to `--lint` (on)

### Phase 2: With Entry Extraction (Priority: High)

4. **Implement pure expression detection**
   - Create `is_pure_expression()` method
   - Handle all literal types, collections, and safe operations

5. **Implement assignment extraction check**
   - Create `can_extract_to_glob()` method
   - Check target types and value purity

6. **Implement module transformation**
   - Process `ModuleCode` nodes
   - Create `GlobalVars` nodes from extractable assignments
   - Update module body

7. **Implement AST node creation**
   - Create proper `GlobalVars` nodes with correct token structure
   - Ensure `normalize()` produces valid output

### Phase 3: Comment Handling (Priority: High)

8. **Implement comment mapping**
   - Build pre-transformation comment-to-node map
   - Track line number relationships

9. **Implement comment transfer**
   - Move comments with extracted code
   - Handle edge cases (block, inline, trailing)

10. **Test with CommentInjectionPass**
    - Verify comments appear correctly after formatting
    - Fix any position calculation issues

### Phase 4: Testing and Polish (Priority: Medium)

11. **Create test fixtures**
    - Simple extraction cases
    - Mixed extractable/non-extractable
    - Comment preservation cases
    - Edge cases (nested, complex expressions)

12. **Add integration tests**
    - Format command with lint on/off
    - Verify AST equivalence
    - Verify formatted output

13. **Documentation**
    - Update CLI help text
    - Add examples to user documentation

---

## Testing Strategy

### Unit Tests

Location: `jac/tests/compiler/passes/tool/test_jac_auto_lint_pass.py`

```python
class TestJacAutoLintPass:
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
```

### Fixture Files

Location: `jac/tests/compiler/passes/tool/fixtures/auto_lint/`

```
auto_lint/
├── simple_extraction.jac
├── simple_extraction.expected.jac
├── mixed_statements.jac
├── mixed_statements.expected.jac
├── with_comments.jac
├── with_comments.expected.jac
├── no_extraction_needed.jac  # Already using glob
├── complex_values.jac        # Non-pure expressions
└── nested_entry.jac          # Named entry blocks (should not be modified)
```

### Integration Tests

```python
def test_format_with_lint(self):
    """Test format command applies linting by default."""
    result = run_cli(['jac', 'format', 'test.jac', '--to_screen'])
    assert 'glob' in result.stdout

def test_format_without_lint(self):
    """Test format command with --no-lint preserves with entry."""
    result = run_cli(['jac', 'format', 'test.jac', '--to_screen', '--no-lint'])
    assert 'with entry' in result.stdout
```

---

## Future Extensions

The auto linting pass architecture is designed to be extensible. Future features could include:

### Planned Features

1. **Import organization**
   - Sort imports alphabetically
   - Group standard library / third-party / local imports
   - Remove unused imports

2. **Redundant code removal**
   - Remove empty `with entry` blocks
   - Remove unused variables (with warning)
   - Simplify redundant expressions

3. **Style consistency**
   - Enforce consistent naming conventions
   - Standardize string quote style
   - Normalize operator spacing

4. **Type annotation suggestions**
   - Add type hints where inferable
   - Suggest return types for functions

### Adding New Lint Rules

Each lint rule should:

1. Be implemented as a separate method
2. Have a corresponding enable/disable flag
3. Include documentation and examples
4. Have dedicated test cases

```jac
class JacAutoLintPass(UniPass) {
    with entry {
        # Feature flags
        lint_with_entry: bool = True;
        lint_imports: bool = True;
        lint_unused: bool = True;
    }

    def enter_module(self: JacAutoLintPass, node: uni.Module) -> None {
        if self.lint_with_entry {
            self.process_entry_blocks(node);
        }
        if self.lint_imports {
            self.organize_imports(node);
        }
    }
}
```

---

## Summary

This implementation plan provides a clean, extensible architecture for the Jac Auto Linting Pass with careful attention to:

1. **Integration**: Fits naturally into the existing pass system
2. **CLI Experience**: On by default with opt-out flag
3. **Comment Preservation**: Leverages existing comment handling infrastructure
4. **Extensibility**: Easy to add new lint rules in the future
5. **Testing**: Comprehensive test strategy for reliability

The first feature (with entry simplification) demonstrates the pattern for future lint rules while providing immediate value to Jac developers.
