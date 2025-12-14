"""Jac Auto Linting Pass for automatic code pattern corrections.

This pass applies automatic linting corrections to Jac code, including:
- Converting unnecessary `with entry` blocks to `glob` declarations
- (Future) Import organization
- (Future) Redundant code removal
"""

import jaclang.pycore.unitree as uni;
import from jaclang.pycore.passes { UniPass }

"""Auto linting pass that applies code style corrections to Jac AST."""
class JacAutoLintPass(UniPass) {
    """Initialize the pass with linting options."""
    with entry {
        changes_made: list[str] = [];
        lint_enabled: bool = True;
        extracted_globals: list[uni.GlobalVars] = [];
        entries_to_remove: list[uni.ModuleCode] = [];
    }

    """Run once before pass begins."""
    def before_pass(self: JacAutoLintPass) -> None {
        self.changes_made = [];
        self.extracted_globals = [];
        self.entries_to_remove = [];
    }

    """Run once after pass completes."""
    def after_pass(self: JacAutoLintPass) -> None {
        # Apply the transformations to the module
        if self.extracted_globals or self.entries_to_remove {
            self.apply_module_transformations();
        }
    }

    """Check if an expression is pure (no side effects)."""
    def is_pure_expression(self: JacAutoLintPass, expr: uni.Expr) -> bool {
        if expr is None {
            return False;
        }

        # Literals are always pure
        if isinstance(expr, (uni.Int, uni.Float, uni.String, uni.Bool, uni.Null)) {
            return True;
        }

        # MultiString (string literals) are pure
        if isinstance(expr, uni.MultiString) {
            # Check if all strings in the multistring are pure
            # (FStrings with expressions might not be pure)
            for s in expr.strings {
                if isinstance(s, uni.FString) {
                    # FString could contain expressions - check them
                    if s.parts is not None {
                        for part in s.parts {
                            if isinstance(part, uni.Expr) and not self.is_pure_expression(part) {
                                return False;
                            }
                        }
                    }
                }
            }
            return True;
        }

        # Simple name references are pure (reading doesn't cause side effects)
        if isinstance(expr, uni.Name) {
            return True;
        }

        # List values - check all elements
        if isinstance(expr, uni.ListVal) {
            if expr.values is None {
                return True;
            }
            for val in expr.values {
                if not self.is_pure_expression(val) {
                    return False;
                }
            }
            return True;
        }

        # Set values - check all elements
        if isinstance(expr, uni.SetVal) {
            if expr.values is None {
                return True;
            }
            for val in expr.values {
                if not self.is_pure_expression(val) {
                    return False;
                }
            }
            return True;
        }

        # Tuple values - check all elements
        if isinstance(expr, uni.TupleVal) {
            if expr.values is None {
                return True;
            }
            for val in expr.values {
                if not self.is_pure_expression(val) {
                    return False;
                }
            }
            return True;
        }

        # Dict values - check all keys and values
        if isinstance(expr, uni.DictVal) {
            if expr.kv_pairs is not None {
                for kv in expr.kv_pairs {
                    if not self.is_pure_expression(kv.key) {
                        return False;
                    }
                    if not self.is_pure_expression(kv.value) {
                        return False;
                    }
                }
            }
            return True;
        }

        # Binary expressions - check both sides
        if isinstance(expr, uni.BinaryExpr) {
            return (
                self.is_pure_expression(expr.left) and
                self.is_pure_expression(expr.right)
            );
        }

        # Unary expressions - check operand
        if isinstance(expr, uni.UnaryExpr) {
            return self.is_pure_expression(expr.operand);
        }

        # Compare expressions - check all parts
        if isinstance(expr, uni.CompareExpr) {
            if not self.is_pure_expression(expr.left) {
                return False;
            }
            for right in expr.rights {
                if not self.is_pure_expression(right) {
                    return False;
                }
            }
            return True;
        }

        # If-else expressions (ternary) - check all parts
        if isinstance(expr, uni.IfElseExpr) {
            return (
                self.is_pure_expression(expr.condition) and
                self.is_pure_expression(expr.value) and
                self.is_pure_expression(expr.else_value)
            );
        }

        # Parenthesized expressions
        if isinstance(expr, uni.ExprAsItem) {
            return self.is_pure_expression(expr.expr);
        }

        # Function calls are NOT pure (could have side effects)
        if isinstance(expr, uni.FuncCall) {
            return False;
        }

        # Attribute access could trigger __getattr__ which may have side effects
        # Be conservative and don't extract these
        if isinstance(expr, uni.AtomTrailer) {
            return False;
        }

        # Index/slice access could trigger __getitem__ which may have side effects
        if isinstance(expr, uni.IndexSlice) {
            return False;
        }

        # Default: not pure (be conservative)
        return False;
    }

    """Check if an assignment can be extracted to a glob statement."""
    def can_extract_to_glob(self: JacAutoLintPass, assignment: uni.Assignment) -> bool {
        # Must have a value (not just declaration)
        if assignment.value is None {
            return False;
        }

        # Must not be an augmented assignment (+=, -= etc.)
        if assignment.aug_op is not None {
            return False;
        }

        # All targets must be simple names
        for target in assignment.target {
            if not isinstance(target, uni.Name) {
                return False;
            }
        }

        # Value must be a pure expression
        return self.is_pure_expression(assignment.value);
    }

    """Check if a statement in with entry block can be extracted."""
    def can_extract_statement(self: JacAutoLintPass, stmt: uni.CodeBlockStmt) -> bool {
        # Only assignments can be extracted
        if not isinstance(stmt, uni.Assignment) {
            return False;
        }
        return self.can_extract_to_glob(stmt);
    }

    """Create a GlobalVars node from an assignment."""
    def create_glob_from_assignment(
        self: JacAutoLintPass,
        assignment: uni.Assignment,
        source_entry: uni.ModuleCode
    ) -> uni.GlobalVars {
        # The GlobalVars node needs initial kids to initialize properly.
        # We provide the assignment as initial kid, then normalize to build
        # the full kid list with the 'glob' keyword token.
        glob_node = uni.GlobalVars(
            access=None,
            assignments=[assignment],
            is_frozen=False,
            kid=[assignment],  # Provide assignment as initial kid for loc resolution
            doc=None
        );

        # Normalize to rebuild the kid list with proper tokens (glob keyword, etc.)
        glob_node.normalize(deep=True);

        return glob_node;
    }

    """Process a with entry block and extract eligible assignments."""
    def process_entry_block(
        self: JacAutoLintPass,
        entry_block: uni.ModuleCode
    ) -> tuple[list[uni.GlobalVars], list[uni.CodeBlockStmt]] {
        extracted: list[uni.GlobalVars] = [];
        remaining: list[uni.CodeBlockStmt] = [];

        for stmt in entry_block.body {
            if self.can_extract_statement(stmt) {
                # Create glob from this assignment
                glob_node = self.create_glob_from_assignment(stmt, entry_block);
                extracted.append(glob_node);
                self.changes_made.append(
                    f"Extracted assignment to glob at line {stmt.loc.first_line}"
                );
            } else {
                remaining.append(stmt);
            }
        }

        return (extracted, remaining);
    }

    """Check if with entry block only contains empty statements."""
    def is_entry_block_empty(self: JacAutoLintPass, body: list[uni.CodeBlockStmt]) -> bool {
        for stmt in body {
            # Check for semi-only statements (EmptyToken with SEMI value)
            if isinstance(stmt, uni.Semi) {
                continue;
            }
            # Any other statement means it's not empty
            return False;
        }
        return True;
    }

    """Process module to find with entry blocks for extraction."""
    def enter_module(self: JacAutoLintPass, node: uni.Module) -> None {
        if not self.lint_enabled {
            return;
        }

        # Find all unnamed with entry blocks (ModuleCode with name=None)
        for stmt in node.body {
            if isinstance(stmt, uni.ModuleCode) and stmt.name is None {
                # This is an unnamed with entry block
                (extracted, remaining) = self.process_entry_block(stmt);

                if extracted {
                    self.extracted_globals.extend(extracted);

                    # Update the entry block's body with remaining statements
                    stmt.body = remaining;

                    # If entry block is now empty, mark for removal
                    if self.is_entry_block_empty(remaining) {
                        self.entries_to_remove.append(stmt);
                        self.changes_made.append(
                            f"Removed empty with entry block at line {stmt.loc.first_line}"
                        );
                    }
                }
            }
        }
    }

    """Apply the collected transformations to the module."""
    def apply_module_transformations(self: JacAutoLintPass) -> None {
        module = self.ir_in;

        # Build new body list
        new_body: list = [];
        insertion_point = 0;
        globs_inserted = False;

        # Find the best insertion point for glob statements
        # (after imports, before other code)
        for (idx, stmt) in enumerate(module.body) {
            if isinstance(stmt, (uni.Import, uni.ModulePath)) {
                insertion_point = idx + 1;
            }
        }

        # Build new body with extracted globs inserted
        for (idx, stmt) in enumerate(module.body) {
            # Insert extracted globals at the insertion point
            if idx == insertion_point and self.extracted_globals and not globs_inserted {
                for glob_stmt in self.extracted_globals {
                    new_body.append(glob_stmt);
                }
                globs_inserted = True;
            }

            # Skip entry blocks marked for removal
            if stmt in self.entries_to_remove {
                continue;
            }

            new_body.append(stmt);
        }

        # Handle case where insertion point is at end or no statements processed
        if not globs_inserted and self.extracted_globals {
            for glob_stmt in self.extracted_globals {
                new_body.append(glob_stmt);
            }
        }

        # Update module body
        module.body = new_body;

        # Recalculate parent references
        self.recalculate_parents(module);

        # Normalize the module to rebuild kid list
        module.normalize(deep=False);
    }
}
