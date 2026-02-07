"""Bootstrap code generator for the Jac bootstrap compiler (Layer 1).

Translates bootstrap AST nodes into Python source text. Generates Python
code as strings, then uses compile() to produce bytecode. This avoids
needing to construct Python ast nodes from Jac.

Written using ONLY the Layer 0 subset so the seed compiler can compile it.
""";

import from jaclang.bootstrap.bootstrap_ast {
    AstNode, ModuleNode, ClassNode, FuncNode, ParamNode, FieldNode,
    ImplNode, GlobNode, ImportNode, ImportName, EnumMemberNode,
    IfNode, ElifNode, WhileNode, ForNode, ReturnNode, BreakNode,
    ContinueNode, AssignNode, AugAssignNode, AnnAssignNode, ExprStmtNode,
    TryNode, ExceptHandler, WithNode, WithItem, AssertNode, DeleteNode,
    PassNode, NameNode, ConstNode, FStringNode, FStringPart,
    BinOpNode, UnaryOpNode, BoolOpNode, CompareNode,
    CallNode, KeywordArg, AttrNode, SubscriptNode, TernaryNode,
    TupleNode, ListNode, DictNode, SetNode,
    ListCompNode, DictCompNode, ComprehensionGen,
    TypeNode, UnionTypeNode, DecoratorNode,
    StarExpr, DblStarExpr, WalrusNode, LambdaNode, SliceNode
}

# =============================================================================
# Codegen
# =============================================================================

obj BootstrapCodegen {
    has indent: int = 0,
        lines: list[str] = [];

    # -------------------------------------------------------------------------
    # Core Output
    # -------------------------------------------------------------------------

    def emit(line: str) -> None {
        prefix = "";
        i = 0;
        while i < self.indent {
            prefix = prefix + "    ";
            i = i + 1;
        }
        self.lines.append(prefix + line);
    }

    def emit_raw(line: str) -> None {
        self.lines.append(line);
    }

    def get_output() -> str {
        result = "";
        for line in self.lines {
            result = result + line + "\n";
        }
        return result;
    }

    def generate(module: ModuleNode) -> str {
        self.lines = [];
        self.indent = 0;
        # Preamble
        self.emit("from __future__ import annotations");
        self.emit("from jaclang.pycore.jaclib import Obj, field");
        self.emit("from enum import Enum");
        self.emit("");
        # Generate body
        for node in module.body {
            self.gen_toplevel(node);
            self.emit("");
        }
        return self.get_output();
    }

    # -------------------------------------------------------------------------
    # Top-level Dispatch
    # -------------------------------------------------------------------------

    def gen_toplevel(node: AstNode) -> None {
        if node.kind == "obj" or node.kind == "class" {
            self.gen_obj(node);
        } elif node.kind == "enum" {
            self.gen_enum(node);
        } elif node.kind == "impl" {
            self.gen_impl(node);
        } elif node.kind == "func" {
            self.gen_function(node, False);
        } elif node.kind == "glob" {
            self.gen_glob(node);
        } elif node.kind == "import" {
            self.gen_import(node);
        } elif node.kind == "expr_stmt" {
            self.emit(self.gen_expr(node.value) + "");
        } elif node.kind == "assign" {
            self.emit(self.gen_expr(node.target) + " = " + self.gen_expr(node.value));
        } elif node.kind == "ann_assign" {
            s = self.gen_expr(node.target) + ": " + self.gen_type(node.type_ann);
            if node.value is not None {
                s = s + " = " + self.gen_expr(node.value);
            }
            self.emit(s);
        } else {
            self.gen_stmt(node);
        }
    }

    # -------------------------------------------------------------------------
    # Object Generation
    # -------------------------------------------------------------------------

    def gen_obj(node: AstNode) -> None {
        # Generate decorators
        for d in node.decorators {
            self.emit("@" + self.gen_expr(d.expr));
        }
        # Base classes
        bases_str = "Obj";
        if len(node.bases) > 0 {
            parts: list[str] = [];
            for b in node.bases {
                parts.append(self.gen_type(b));
            }
            bases_str = self.join_strs(parts, ", ") + ", Obj";
        }
        self.emit("class " + node.name + "(" + bases_str + "):");
        self.indent = self.indent + 1;
        if len(node.body) == 0 {
            self.emit("pass");
        } else {
            for member in node.body {
                if member.kind == "field" {
                    self.gen_field(member);
                } elif member.kind == "func" {
                    self.gen_function(member, True);
                } elif member.kind == "pass" {
                    self.emit("pass");
                } else {
                    self.gen_stmt(member);
                }
            }
        }
        self.indent = self.indent - 1;
    }

    # -------------------------------------------------------------------------
    # Enum Generation
    # -------------------------------------------------------------------------

    def gen_enum(node: AstNode) -> None {
        for d in node.decorators {
            self.emit("@" + self.gen_expr(d.expr));
        }
        bases_str = "Enum";
        if len(node.bases) > 0 {
            parts: list[str] = [];
            for b in node.bases {
                parts.append(self.gen_type(b));
            }
            bases_str = self.join_strs(parts, ", ");
        }
        self.emit("class " + node.name + "(" + bases_str + "):");
        self.indent = self.indent + 1;
        if len(node.body) == 0 {
            self.emit("pass");
        } else {
            for member in node.body {
                if member.kind == "enum_member" {
                    if member.value is not None {
                        self.emit(member.name + " = " + self.gen_expr(member.value));
                    } else {
                        self.emit(member.name + " = auto()");
                    }
                } else {
                    self.gen_stmt(member);
                }
            }
        }
        self.indent = self.indent - 1;
    }

    # -------------------------------------------------------------------------
    # Impl Generation
    # -------------------------------------------------------------------------

    def gen_impl(node: AstNode) -> None {
        target = node.target;
        for method in node.methods {
            mangled = "_impl_" + target + "_" + method.name;
            self.gen_impl_method(method, mangled);
            self.emit(target + "." + method.name + " = " + mangled);
            self.emit("");
        }
    }

    def gen_impl_method(node: AstNode, mangled_name: str) -> None {
        for d in node.decorators {
            self.emit("@" + self.gen_expr(d.expr));
        }
        params_str = self.gen_params(node.params, True);
        ret_str = "";
        if node.return_type is not None {
            ret_str = " -> " + self.gen_type(node.return_type);
        }
        self.emit("def " + mangled_name + "(" + params_str + ")" + ret_str + ":");
        self.indent = self.indent + 1;
        if node.is_abstract or len(node.body) == 0 {
            self.emit("...");
        } else {
            for stmt in node.body {
                self.gen_stmt(stmt);
            }
        }
        self.indent = self.indent - 1;
    }

    # -------------------------------------------------------------------------
    # Function Generation
    # -------------------------------------------------------------------------

    def gen_function(node: AstNode, is_method: bool) -> None {
        for d in node.decorators {
            self.emit("@" + self.gen_expr(d.expr));
        }
        params_str = self.gen_params(node.params, is_method);
        ret_str = "";
        if node.return_type is not None {
            ret_str = " -> " + self.gen_type(node.return_type);
        }
        self.emit("def " + node.name + "(" + params_str + ")" + ret_str + ":");
        self.indent = self.indent + 1;
        if node.is_abstract or len(node.body) == 0 {
            self.emit("...");
        } else {
            for stmt in node.body {
                self.gen_stmt(stmt);
            }
        }
        self.indent = self.indent - 1;
    }

    def gen_params(params: list[AstNode], add_self: bool) -> str {
        parts: list[str] = [];
        if add_self {
            has_self = False;
            if len(params) > 0 {
                if params[0].name == "self" {
                    has_self = True;
                }
            }
            if not has_self {
                parts.append("self");
            }
        }
        for p in params {
            s = "";
            if p.is_dstar {
                s = "**";
            } elif p.is_star {
                s = "*";
            }
            s = s + p.name;
            if p.type_ann is not None {
                s = s + ": " + self.gen_type(p.type_ann);
            }
            if p.default is not None {
                s = s + " = " + self.gen_expr(p.default);
            }
            parts.append(s);
        }
        return self.join_strs(parts, ", ");
    }

    # -------------------------------------------------------------------------
    # Field Generation
    # -------------------------------------------------------------------------

    def gen_field(node: AstNode) -> None {
        type_str = self.gen_type(node.type_ann);
        if node.default is not None {
            val_str = self.gen_expr(node.default);
            if self.is_mutable_default(node.default) {
                self.emit(node.name + ": " + type_str + " = field(factory=lambda: " + val_str + ")");
            } else {
                self.emit(node.name + ": " + type_str + " = " + val_str);
            }
        } else {
            self.emit(node.name + ": " + type_str);
        }
    }

    def is_mutable_default(node: AstNode) -> bool {
        return node.kind == "list" or node.kind == "dict" or node.kind == "set";
    }

    # -------------------------------------------------------------------------
    # Import Generation
    # -------------------------------------------------------------------------

    def gen_import(node: AstNode) -> None {
        if node.is_from {
            names_parts: list[str] = [];
            for n in node.names {
                if n.alias is not None {
                    names_parts.append(n.name + " as " + n.alias);
                } else {
                    names_parts.append(n.name);
                }
            }
            names_str = self.join_strs(names_parts, ", ");
            self.emit("from " + node.module + " import " + names_str);
        } else {
            self.emit("import " + node.module);
        }
    }

    # -------------------------------------------------------------------------
    # Glob Generation
    # -------------------------------------------------------------------------

    def gen_glob(node: AstNode) -> None {
        if node.type_ann is not None {
            s = node.name + ": " + self.gen_type(node.type_ann);
            if node.value is not None {
                s = s + " = " + self.gen_expr(node.value);
            }
            self.emit(s);
        } elif node.value is not None {
            self.emit(node.name + " = " + self.gen_expr(node.value));
        }
    }

    # -------------------------------------------------------------------------
    # Statement Generation
    # -------------------------------------------------------------------------

    def gen_stmt(node: AstNode) -> None {
        if node.kind == "if" {
            self.gen_if(node);
        } elif node.kind == "while" {
            self.gen_while(node);
        } elif node.kind == "for" {
            self.gen_for(node);
        } elif node.kind == "return" {
            if node.value is not None {
                self.emit("return " + self.gen_expr(node.value));
            } else {
                self.emit("return");
            }
        } elif node.kind == "break" {
            self.emit("break");
        } elif node.kind == "continue" {
            self.emit("continue");
        } elif node.kind == "pass" {
            self.emit("pass");
        } elif node.kind == "assign" {
            self.emit(self.gen_expr(node.target) + " = " + self.gen_expr(node.value));
        } elif node.kind == "aug_assign" {
            self.emit(self.gen_expr(node.target) + " " + node.op + " " + self.gen_expr(node.value));
        } elif node.kind == "ann_assign" {
            s = self.gen_expr(node.target) + ": " + self.gen_type(node.type_ann);
            if node.value is not None {
                s = s + " = " + self.gen_expr(node.value);
            }
            self.emit(s);
        } elif node.kind == "expr_stmt" {
            self.emit(self.gen_expr(node.value));
        } elif node.kind == "try" {
            self.gen_try(node);
        } elif node.kind == "with" {
            self.gen_with(node);
        } elif node.kind == "assert" {
            s = "assert " + self.gen_expr(node.test);
            if node.msg is not None {
                s = s + ", " + self.gen_expr(node.msg);
            }
            self.emit(s);
        } elif node.kind == "del" {
            parts: list[str] = [];
            for t in node.targets {
                parts.append(self.gen_expr(t));
            }
            self.emit("del " + self.join_strs(parts, ", "));
        } elif node.kind == "raise" {
            if node.value is not None {
                self.emit("raise " + self.gen_expr(node.value));
            } else {
                self.emit("raise");
            }
        } elif node.kind == "func" {
            self.gen_function(node, False);
        } elif node.kind == "field" {
            self.gen_field(node);
        } elif node.kind == "glob" {
            self.gen_glob(node);
        } elif node.kind == "import" {
            self.gen_import(node);
        } elif node.kind == "obj" or node.kind == "class" {
            self.gen_obj(node);
        } elif node.kind == "enum" {
            self.gen_enum(node);
        } elif node.kind == "impl" {
            self.gen_impl(node);
        } else {
            self.emit("# UNKNOWN: " + node.kind);
        }
    }

    # -------------------------------------------------------------------------
    # Control Flow Generation
    # -------------------------------------------------------------------------

    def gen_if(node: AstNode) -> None {
        self.emit("if " + self.gen_expr(node.test) + ":");
        self.indent = self.indent + 1;
        if len(node.body) == 0 {
            self.emit("pass");
        } else {
            for s in node.body {
                self.gen_stmt(s);
            }
        }
        self.indent = self.indent - 1;
        for elif_branch in node.elif_branches {
            self.emit("elif " + self.gen_expr(elif_branch.test) + ":");
            self.indent = self.indent + 1;
            if len(elif_branch.body) == 0 {
                self.emit("pass");
            } else {
                for s in elif_branch.body {
                    self.gen_stmt(s);
                }
            }
            self.indent = self.indent - 1;
        }
        if len(node.else_body) > 0 {
            self.emit("else:");
            self.indent = self.indent + 1;
            for s in node.else_body {
                self.gen_stmt(s);
            }
            self.indent = self.indent - 1;
        }
    }

    def gen_while(node: AstNode) -> None {
        self.emit("while " + self.gen_expr(node.test) + ":");
        self.indent = self.indent + 1;
        if len(node.body) == 0 {
            self.emit("pass");
        } else {
            for s in node.body {
                self.gen_stmt(s);
            }
        }
        self.indent = self.indent - 1;
    }

    def gen_for(node: AstNode) -> None {
        target_str = self.gen_expr(node.target);
        self.emit("for " + target_str + " in " + self.gen_expr(node.iter) + ":");
        self.indent = self.indent + 1;
        if len(node.body) == 0 {
            self.emit("pass");
        } else {
            for s in node.body {
                self.gen_stmt(s);
            }
        }
        self.indent = self.indent - 1;
    }

    def gen_try(node: AstNode) -> None {
        self.emit("try:");
        self.indent = self.indent + 1;
        if len(node.body) == 0 {
            self.emit("pass");
        } else {
            for s in node.body {
                self.gen_stmt(s);
            }
        }
        self.indent = self.indent - 1;
        for handler in node.handlers {
            s = "except";
            if handler.exc_type is not None {
                s = s + " " + self.gen_expr(handler.exc_type);
                if handler.name is not None {
                    s = s + " as " + handler.name;
                }
            }
            self.emit(s + ":");
            self.indent = self.indent + 1;
            if len(handler.body) == 0 {
                self.emit("pass");
            } else {
                for hs in handler.body {
                    self.gen_stmt(hs);
                }
            }
            self.indent = self.indent - 1;
        }
        if len(node.else_body) > 0 {
            self.emit("else:");
            self.indent = self.indent + 1;
            for s in node.else_body {
                self.gen_stmt(s);
            }
            self.indent = self.indent - 1;
        }
        if len(node.finally_body) > 0 {
            self.emit("finally:");
            self.indent = self.indent + 1;
            for s in node.finally_body {
                self.gen_stmt(s);
            }
            self.indent = self.indent - 1;
        }
    }

    def gen_with(node: AstNode) -> None {
        items_parts: list[str] = [];
        for item in node.items {
            s = self.gen_expr(item.context);
            if item.var is not None {
                s = s + " as " + self.gen_expr(item.var);
            }
            items_parts.append(s);
        }
        self.emit("with " + self.join_strs(items_parts, ", ") + ":");
        self.indent = self.indent + 1;
        if len(node.body) == 0 {
            self.emit("pass");
        } else {
            for s in node.body {
                self.gen_stmt(s);
            }
        }
        self.indent = self.indent - 1;
    }

    # -------------------------------------------------------------------------
    # Expression Generation
    # -------------------------------------------------------------------------

    def gen_expr(node: AstNode) -> str {
        if node is None {
            return "None";
        }
        if node.kind == "name" {
            return node.name;
        }
        if node.kind == "const" {
            return self.gen_const(node);
        }
        if node.kind == "fstring" {
            return self.gen_fstring(node);
        }
        if node.kind == "bin_op" {
            return "(" + self.gen_expr(node.left) + " " + node.op + " " + self.gen_expr(node.right) + ")";
        }
        if node.kind == "unary_op" {
            if node.op == "not" {
                return "(not " + self.gen_expr(node.operand) + ")";
            }
            return "(" + node.op + self.gen_expr(node.operand) + ")";
        }
        if node.kind == "bool_op" {
            parts: list[str] = [];
            for v in node.values {
                parts.append(self.gen_expr(v));
            }
            sep = " " + node.op + " ";
            return "(" + self.join_strs(parts, sep) + ")";
        }
        if node.kind == "compare" {
            s = self.gen_expr(node.left);
            i = 0;
            while i < len(node.ops) {
                s = s + " " + node.ops[i] + " " + self.gen_expr(node.comparators[i]);
                i = i + 1;
            }
            return "(" + s + ")";
        }
        if node.kind == "call" {
            return self.gen_call(node);
        }
        if node.kind == "attr" {
            return self.gen_expr(node.value) + "." + node.attr;
        }
        if node.kind == "subscript" {
            return self.gen_expr(node.value) + "[" + self.gen_subscript_index(node.index) + "]";
        }
        if node.kind == "ternary" {
            return "(" + self.gen_expr(node.body) + " if " + self.gen_expr(node.test) + " else " + self.gen_expr(node.orelse) + ")";
        }
        if node.kind == "tuple" {
            if len(node.elts) == 0 {
                return "()";
            }
            if len(node.elts) == 1 {
                return "(" + self.gen_expr(node.elts[0]) + ",)";
            }
            parts = [];
            for e in node.elts {
                parts.append(self.gen_expr(e));
            }
            return "(" + self.join_strs(parts, ", ") + ")";
        }
        if node.kind == "list" {
            parts = [];
            for e in node.elts {
                parts.append(self.gen_expr(e));
            }
            return "[" + self.join_strs(parts, ", ") + "]";
        }
        if node.kind == "dict" {
            parts = [];
            i = 0;
            while i < len(node.keys) {
                parts.append(self.gen_expr(node.keys[i]) + ": " + self.gen_expr(node.values[i]));
                i = i + 1;
            }
            return "{" + self.join_strs(parts, ", ") + "}";
        }
        if node.kind == "set" {
            parts = [];
            for e in node.elts {
                parts.append(self.gen_expr(e));
            }
            return "{" + self.join_strs(parts, ", ") + "}";
        }
        if node.kind == "list_comp" {
            return self.gen_list_comp(node);
        }
        if node.kind == "dict_comp" {
            return self.gen_dict_comp(node);
        }
        if node.kind == "star" {
            return "*" + self.gen_expr(node.value);
        }
        if node.kind == "dblstar" {
            return "**" + self.gen_expr(node.value);
        }
        if node.kind == "walrus" {
            return "(" + self.gen_expr(node.target) + " := " + self.gen_expr(node.value) + ")";
        }
        if node.kind == "lambda" {
            params_str = self.gen_params(node.params, False);
            return "(lambda " + params_str + ": " + self.gen_expr(node.body) + ")";
        }
        if node.kind == "slice" {
            return self.gen_slice(node);
        }
        return "None  # UNKNOWN_EXPR: " + node.kind;
    }

    def gen_const(node: AstNode) -> str {
        if node.const_type == "str" {
            return node.value;
        }
        if node.const_type == "int" {
            return node.value;
        }
        if node.const_type == "float" {
            return node.value;
        }
        if node.const_type == "bool" {
            return node.value;
        }
        if node.const_type == "none" {
            return "None";
        }
        return node.value;
    }

    def gen_fstring(node: AstNode) -> str {
        s = "f\"";
        for part in node.parts {
            if part.is_expr {
                s = s + "{" + self.gen_expr(part.expr) + "}";
            } else {
                s = s + part.text;
            }
        }
        s = s + "\"";
        return s;
    }

    def gen_call(node: AstNode) -> str {
        func_str = self.gen_expr(node.func);
        arg_parts: list[str] = [];
        for a in node.args {
            arg_parts.append(self.gen_expr(a));
        }
        for kw in node.kwargs {
            if kw.name is not None {
                arg_parts.append(kw.name + "=" + self.gen_expr(kw.value));
            } else {
                # **kwargs
                arg_parts.append(self.gen_expr(kw.value));
            }
        }
        return func_str + "(" + self.join_strs(arg_parts, ", ") + ")";
    }

    def gen_subscript_index(node: AstNode) -> str {
        if node.kind == "slice" {
            return self.gen_slice(node);
        }
        return self.gen_expr(node);
    }

    def gen_slice(node: AstNode) -> str {
        s = "";
        if node.lower is not None {
            s = self.gen_expr(node.lower);
        }
        s = s + ":";
        if node.upper is not None {
            s = s + self.gen_expr(node.upper);
        }
        if node.step is not None {
            s = s + ":" + self.gen_expr(node.step);
        }
        return s;
    }

    # -------------------------------------------------------------------------
    # Comprehension Generation
    # -------------------------------------------------------------------------

    def gen_list_comp(node: AstNode) -> str {
        s = "[" + self.gen_expr(node.elt);
        for gen in node.generators {
            s = s + " for " + self.gen_expr(gen.target) + " in " + self.gen_expr(gen.iter);
            for cond in gen.ifs {
                s = s + " if " + self.gen_expr(cond);
            }
        }
        s = s + "]";
        return s;
    }

    def gen_dict_comp(node: AstNode) -> str {
        s = "{" + self.gen_expr(node.key) + ": " + self.gen_expr(node.value);
        for gen in node.generators {
            s = s + " for " + self.gen_expr(gen.target) + " in " + self.gen_expr(gen.iter);
            for cond in gen.ifs {
                s = s + " if " + self.gen_expr(cond);
            }
        }
        s = s + "}";
        return s;
    }

    # -------------------------------------------------------------------------
    # Type Expression Generation
    # -------------------------------------------------------------------------

    def gen_type(node: AstNode | None) -> str {
        if node is None {
            return "Any";
        }
        if node.kind == "name" {
            return node.name;
        }
        if node.kind == "type" {
            if len(node.args) == 0 {
                return node.name;
            }
            arg_parts: list[str] = [];
            for a in node.args {
                arg_parts.append(self.gen_type(a));
            }
            return node.name + "[" + self.join_strs(arg_parts, ", ") + "]";
        }
        if node.kind == "union_type" {
            parts: list[str] = [];
            for t in node.types {
                parts.append(self.gen_type(t));
            }
            return self.join_strs(parts, " | ");
        }
        if node.kind == "attr" {
            return self.gen_expr(node);
        }
        if node.kind == "subscript" {
            return self.gen_expr(node);
        }
        if node.kind == "const" {
            return self.gen_const(node);
        }
        return self.gen_expr(node);
    }

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    def join_strs(parts: list[str], sep: str) -> str {
        result = "";
        i = 0;
        while i < len(parts) {
            if i > 0 {
                result = result + sep;
            }
            result = result + parts[i];
            i = i + 1;
        }
        return result;
    }
}
