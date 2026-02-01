# ruff: noqa: N802
"""Transform ESTree JSON AST (from oxc-parser) into Jac uni.* AST nodes.

This module converts the standard ESTree/TS-ESTree JSON representation into
Jac's unified AST (unitree), preserving source locations from the original
TypeScript/JavaScript source files for goto-definition support.

Method names like _transform_ImportDeclaration match ESTree node types
and are dispatched dynamically via getattr().
"""

from __future__ import annotations

import os
from collections.abc import Sequence
from typing import Any, cast

import jaclang.pycore.unitree as uni
from jaclang.pycore.constant import Tokens as Tok


class EsTreeToUniAst:
    """Transforms an ESTree JSON dict into a uni.Module."""

    def __init__(self, source: uni.Source, file_path: str) -> None:
        self.source = source
        self.file_path = file_path
        self.mod_name = os.path.basename(file_path).split(".")[0]
        self.terminals: list[uni.Token] = []

    # -------------------------------------------------------------------------
    # Public entry point
    # -------------------------------------------------------------------------

    def transform(self, estree: dict[str, Any]) -> uni.Module:
        """Transform an ESTree parse result dict into a uni.Module."""
        program = estree.get("program", {})
        body_nodes = program.get("body", [])

        stmts: list[uni.ElementStmt | uni.String | uni.EmptyToken] = []
        for node in body_nodes:
            result = self._transform_node(node)
            if result is not None:
                if isinstance(result, list):
                    stmts.extend(result)  # type: ignore[arg-type]
                else:
                    stmts.append(result)  # type: ignore[arg-type]

        kid: list[uni.UniNode] = list(stmts) if stmts else [uni.EmptyToken(self.source)]
        mod = uni.Module(
            name=self.mod_name,
            source=self.source,
            doc=None,
            body=stmts,
            terminals=self.terminals,
            kid=kid,
        )
        return mod

    # -------------------------------------------------------------------------
    # Node dispatcher
    # -------------------------------------------------------------------------

    def _transform_node(
        self, node: dict[str, Any]
    ) -> uni.UniNode | list[uni.UniNode] | None:
        """Dispatch to the appropriate handler based on ESTree node type."""
        if node is None:
            return None
        node_type = node.get("type", "")
        handler = getattr(self, f"_transform_{node_type}", None)
        if handler:
            return handler(node)
        # For unrecognized node types, return None (skip)
        return None

    # -------------------------------------------------------------------------
    # Location helpers
    # -------------------------------------------------------------------------

    def _make_token(
        self,
        name: str,
        value: str,
        node: dict[str, Any],
    ) -> uni.Token:
        """Create a uni.Token from an ESTree node's location."""
        loc = node.get("loc", {})
        start = loc.get("start", {})
        end = loc.get("end", {})
        rng = node.get("range", [0, 0])
        tok = uni.Token(
            orig_src=self.source,
            name=name,
            value=value,
            line=start.get("line", 1),
            end_line=end.get("line", 1),
            col_start=start.get("column", 0),
            col_end=end.get("column", 0),
            pos_start=rng[0] if len(rng) > 0 else 0,
            pos_end=rng[1] if len(rng) > 1 else 0,
        )
        self.terminals.append(tok)
        return tok

    def _make_name(self, node: dict[str, Any]) -> uni.Name:
        """Create a uni.Name from an ESTree Identifier node."""
        value = node.get("name", node.get("value", ""))
        loc = node.get("loc", {})
        start = loc.get("start", {})
        end = loc.get("end", {})
        rng = node.get("range", [0, 0])
        name = uni.Name(
            orig_src=self.source,
            name=Tok.NAME.value,
            value=str(value),
            line=start.get("line", 1),
            end_line=end.get("line", 1),
            col_start=start.get("column", 0),
            col_end=end.get("column", 0),
            pos_start=rng[0] if len(rng) > 0 else 0,
            pos_end=rng[1] if len(rng) > 1 else 0,
        )
        self.terminals.append(name)
        return name

    def _make_name_from_str(self, value: str, parent_node: dict[str, Any]) -> uni.Name:
        """Create a uni.Name with location borrowed from a parent node."""
        loc = parent_node.get("loc", {})
        start = loc.get("start", {})
        end = loc.get("end", {})
        rng = parent_node.get("range", [0, 0])
        name = uni.Name(
            orig_src=self.source,
            name=Tok.NAME.value,
            value=value,
            line=start.get("line", 1),
            end_line=end.get("line", 1),
            col_start=start.get("column", 0),
            col_end=end.get("column", 0),
            pos_start=rng[0] if len(rng) > 0 else 0,
            pos_end=rng[1] if len(rng) > 1 else 0,
        )
        self.terminals.append(name)
        return name

    def _make_type_name(self, node: dict[str, Any]) -> uni.Name:
        """Create a uni.Name from a TS type annotation node (type keyword or reference)."""
        node_type = node.get("type", "")

        # Primitive type keywords
        type_keyword_map = {
            "TSStringKeyword": "str",
            "TSNumberKeyword": "float",
            "TSBooleanKeyword": "bool",
            "TSVoidKeyword": "None",
            "TSNullKeyword": "None",
            "TSUndefinedKeyword": "None",
            "TSAnyKeyword": "any",
            "TSUnknownKeyword": "unknown",
            "TSNeverKeyword": "never",
            "TSObjectKeyword": "object",
            "TSBigIntKeyword": "int",
            "TSSymbolKeyword": "symbol",
        }

        if node_type in type_keyword_map:
            return self._make_name_from_str(type_keyword_map[node_type], node)

        if node_type == "TSTypeReference":
            type_name_node = node.get("typeName")
            if type_name_node:
                return self._make_name(type_name_node)
            return self._make_name_from_str("unknown", node)

        if node_type == "TSArrayType":
            return self._make_name_from_str("list", node)

        if node_type == "TSUnionType":
            # For union types, create a name representing the union
            types = node.get("types", [])
            type_names = []
            for t in types:
                tn = self._make_type_name(t)
                type_names.append(tn.value)
            return self._make_name_from_str(" | ".join(type_names), node)

        if node_type == "TSIntersectionType":
            types = node.get("types", [])
            type_names = []
            for t in types:
                tn = self._make_type_name(t)
                type_names.append(tn.value)
            return self._make_name_from_str(" & ".join(type_names), node)

        if node_type == "TSFunctionType":
            return self._make_name_from_str("Callable", node)

        if node_type == "TSTupleType":
            return self._make_name_from_str("tuple", node)

        if node_type == "TSLiteralType":
            literal = node.get("literal", {})
            val = literal.get("value", literal.get("raw", ""))
            return self._make_name_from_str(str(val), node)

        if node_type == "TSTypeLiteral":
            return self._make_name_from_str("dict", node)

        # Fallback
        return self._make_name_from_str("any", node)

    def _make_type_tag(
        self, annotation: dict[str, Any] | None
    ) -> uni.SubTag[uni.Expr] | None:
        """Create a SubTag type annotation from a TSTypeAnnotation node."""
        if annotation is None:
            return None

        # TSTypeAnnotation wraps the actual type
        inner = annotation
        if annotation.get("type") == "TSTypeAnnotation":
            inner = annotation.get("typeAnnotation", annotation)

        type_name = self._make_type_name(inner)
        return uni.SubTag(tag=type_name, kid=[type_name])

    # -------------------------------------------------------------------------
    # Import / Export handlers
    # -------------------------------------------------------------------------

    def _transform_ImportDeclaration(self, node: dict[str, Any]) -> uni.Import:
        """Transform ESTree ImportDeclaration → uni.Import."""
        source_node = node.get("source", {})
        source_value = source_node.get("value", "")

        # Build ModulePath from the import source string
        path_name = self._make_name_from_str(source_value, source_node)
        mod_path = uni.ModulePath(
            path=[path_name],
            level=0,
            alias=None,
            kid=[path_name],
        )

        # Build ModuleItems from specifiers
        specifiers = node.get("specifiers", [])
        items: list[uni.ModuleItem] = []
        for spec in specifiers:
            spec_type = spec.get("type", "")
            if spec_type == "ImportSpecifier":
                imported = spec.get("imported", {})
                local = spec.get("local", {})
                name = self._make_name(imported)
                alias = (
                    self._make_name(local)
                    if local.get("name") != imported.get("name")
                    else None
                )
                items.append(uni.ModuleItem(name=name, alias=alias, kid=[name]))
            elif spec_type == "ImportDefaultSpecifier":
                local = spec.get("local", {})
                name_tok = self._make_token(Tok.KW_DEFAULT.value, "default", spec)
                alias = self._make_name(local)
                items.append(uni.ModuleItem(name=name_tok, alias=alias, kid=[name_tok]))
            elif spec_type == "ImportNamespaceSpecifier":
                local = spec.get("local", {})
                name_tok = self._make_token(Tok.STAR_MUL.value, "*", spec)
                alias = self._make_name(local)
                items.append(uni.ModuleItem(name=name_tok, alias=alias, kid=[name_tok]))

        all_kids: list[uni.UniNode] = [mod_path, *items]
        return uni.Import(
            from_loc=mod_path,
            items=items,
            is_absorb=False,
            kid=all_kids,
        )

    def _transform_ExportNamedDeclaration(
        self, node: dict[str, Any]
    ) -> uni.UniNode | list[uni.UniNode] | None:
        """Transform ExportNamedDeclaration → underlying declaration."""
        decl = node.get("declaration")
        if decl:
            return self._transform_node(decl)
        # Re-export: export { foo } from 'bar'
        source_node = node.get("source")
        if source_node:
            return self._transform_ImportDeclaration(
                {
                    **node,
                    "specifiers": node.get("specifiers", []),
                    "source": source_node,
                }
            )
        return None

    def _transform_ExportDefaultDeclaration(
        self, node: dict[str, Any]
    ) -> uni.UniNode | list[uni.UniNode] | None:
        """Transform ExportDefaultDeclaration → underlying declaration."""
        decl = node.get("declaration")
        if decl:
            return self._transform_node(decl)
        return None

    def _transform_ExportAllDeclaration(
        self, node: dict[str, Any]
    ) -> uni.Import | None:
        """Transform ExportAllDeclaration (export * from 'mod')."""
        source_node = node.get("source")
        if not source_node:
            return None
        source_value = source_node.get("value", "")
        path_name = self._make_name_from_str(source_value, source_node)
        mod_path = uni.ModulePath(
            path=[path_name], level=0, alias=None, kid=[path_name]
        )
        star_tok = self._make_token(Tok.STAR_MUL.value, "*", node)
        item = uni.ModuleItem(name=star_tok, alias=None, kid=[star_tok])
        return uni.Import(
            from_loc=mod_path,
            items=[item],
            is_absorb=False,
            kid=[mod_path, item],
        )

    # -------------------------------------------------------------------------
    # Variable declarations
    # -------------------------------------------------------------------------

    def _transform_VariableDeclaration(self, node: dict[str, Any]) -> uni.GlobalVars:
        """Transform VariableDeclaration → uni.GlobalVars."""
        kind = node.get("kind", "let")
        is_frozen = kind == "const"
        declarators = node.get("declarations", [])

        assignments: list[uni.Assignment] = []
        for decl in declarators:
            assignment = self._transform_VariableDeclarator(decl)
            if assignment:
                assignments.append(assignment)

        kids: list[uni.UniNode] = list(assignments)
        return uni.GlobalVars(
            access=None,
            assignments=assignments,
            is_frozen=is_frozen,
            kid=kids,
        )

    def _transform_VariableDeclarator(
        self, node: dict[str, Any]
    ) -> uni.Assignment | None:
        """Transform VariableDeclarator → uni.Assignment."""
        id_node = node.get("id", {})
        if not id_node:
            return None

        # Handle Identifier pattern
        type_annotation = id_node.get("typeAnnotation")

        if id_node.get("type") == "Identifier":
            name = self._make_name(id_node)
        else:
            # Destructuring patterns — use a placeholder name
            name = self._make_name_from_str("_destructured", node)

        type_tag = self._make_type_tag(type_annotation)

        # Transform init value
        init = node.get("init")
        value = self._transform_expr(init) if init else None

        kids: list[uni.UniNode] = [name]
        if type_tag:
            kids.append(type_tag)
        if value:
            kids.append(value)

        return uni.Assignment(
            target=[name],
            value=value,
            type_tag=type_tag,
            kid=kids,
        )

    # -------------------------------------------------------------------------
    # Function declarations
    # -------------------------------------------------------------------------

    def _transform_FunctionDeclaration(self, node: dict[str, Any]) -> uni.Ability:
        """Transform FunctionDeclaration → uni.Ability."""
        id_node = node.get("id")
        name = (
            self._make_name(id_node)
            if id_node
            else self._make_name_from_str("__anonymous__", node)
        )
        is_async = node.get("async", False)
        params = self._transform_params(node.get("params", []))
        return_type_ann = node.get("returnType")
        return_type_tag = self._make_type_tag(return_type_ann)

        sig_kids: list[uni.UniNode] = [
            *params,
            *([] if return_type_tag is None else [return_type_tag]),
        ]
        if not sig_kids:
            sig_kids = [self._make_token("LPAREN", "(", node)]

        sig = uni.FuncSignature(
            posonly_params=[],
            params=params,
            varargs=None,
            kwonlyargs=[],
            kwargs=None,
            return_type=return_type_tag.tag if return_type_tag else None,
            kid=sig_kids,
        )

        kids: list[uni.UniNode] = [name, sig]
        return uni.Ability(
            name_ref=name,
            is_async=is_async,
            is_override=False,
            is_static=False,
            is_abstract=False,
            access=None,
            signature=sig,
            body=None,  # We don't need function bodies for type checking
            kid=kids,
        )

    def _transform_params(self, params: list[dict[str, Any]]) -> list[uni.ParamVar]:
        """Transform a list of ESTree parameter nodes → list of uni.ParamVar."""
        result: list[uni.ParamVar] = []
        for param in params:
            pv = self._transform_param(param)
            if pv:
                result.append(pv)
        return result

    def _transform_param(self, param: dict[str, Any]) -> uni.ParamVar | None:
        """Transform a single ESTree parameter → uni.ParamVar."""
        param_type = param.get("type", "")

        if param_type == "Identifier":
            name = self._make_name(param)
            type_ann = param.get("typeAnnotation")
            type_tag = self._make_type_tag(type_ann)
            kids: list[uni.UniNode] = [name]
            if type_tag:
                kids.append(type_tag)
            return uni.ParamVar(
                name=name,
                unpack=None,
                type_tag=type_tag,  # type: ignore[arg-type]
                value=None,
                kid=kids,
            )

        if param_type == "AssignmentPattern":
            left = param.get("left", {})
            right = param.get("right")
            inner = self._transform_param(left)
            if inner and right:
                inner.value = self._transform_expr(right)
            return inner

        if param_type == "RestElement":
            argument = param.get("argument", {})
            if argument.get("type") == "Identifier":
                name = self._make_name(argument)
                type_ann = argument.get("typeAnnotation") or param.get("typeAnnotation")
                type_tag = self._make_type_tag(type_ann)
                star_tok = self._make_token(Tok.STAR_MUL.value, "*", param)
                kids = [star_tok, name]
                if type_tag:
                    kids.append(type_tag)
                return uni.ParamVar(
                    name=name,
                    unpack=star_tok,
                    type_tag=type_tag,  # type: ignore[arg-type]
                    value=None,
                    kid=kids,
                )

        # For complex patterns (object/array destructuring), create a placeholder
        name = self._make_name_from_str("_param", param)
        return uni.ParamVar(
            name=name,
            unpack=None,
            type_tag=None,  # type: ignore[arg-type]
            value=None,
            kid=[name],
        )

    # -------------------------------------------------------------------------
    # Class declarations
    # -------------------------------------------------------------------------

    def _transform_ClassDeclaration(self, node: dict[str, Any]) -> uni.Archetype:
        """Transform ClassDeclaration → uni.Archetype."""
        id_node = node.get("id")
        name = (
            self._make_name(id_node)
            if id_node
            else self._make_name_from_str("__anonymous_class__", node)
        )

        arch_type_tok = self._make_token("KW_CLASS", "class", node)

        # Base classes
        super_class = node.get("superClass")
        base_classes: list[uni.Expr] = []
        if super_class and super_class.get("type") == "Identifier":
            base_name = self._make_name(super_class)
            base_classes.append(base_name)

        # Class body
        body_node = node.get("body", {})
        body_items = body_node.get("body", [])
        body: list[uni.ArchBlockStmt] = []

        for item in body_items:
            result = self._transform_class_member(item)
            if result:
                body.append(result)

        # Decorators
        decorators_raw = node.get("decorators", [])
        decorators = self._transform_decorators(decorators_raw)

        kids: list[uni.UniNode] = [name, arch_type_tok, *body]
        return uni.Archetype(
            name=name,
            arch_type=arch_type_tok,
            access=None,
            base_classes=base_classes if base_classes else None,
            body=body if body else None,
            kid=kids,
            decorators=decorators,
        )

    def _transform_class_member(self, node: dict[str, Any]) -> uni.ArchBlockStmt | None:
        """Transform a class body member (method, property, etc.)."""
        node_type = node.get("type", "")

        if node_type == "MethodDefinition":
            return self._transform_MethodDefinition(node)
        elif node_type == "PropertyDefinition":
            has_var = self._transform_PropertyDefinition(node)
            is_static = node.get("static", False)
            access_str = node.get("accessibility")
            access = None
            if access_str:
                acc_tok = self._make_token("ACCESS", access_str, node)
                access = uni.SubTag(tag=acc_tok, kid=[acc_tok])
            return uni.ArchHas(
                is_static=is_static,
                access=access,
                vars=[has_var],
                is_frozen=False,
                kid=[has_var],
            )
        elif node_type == "TSIndexSignature":
            return None  # Skip index signatures for now
        elif node_type == "StaticBlock":
            return None  # Skip static blocks

        return None

    def _transform_MethodDefinition(self, node: dict[str, Any]) -> uni.Ability:
        """Transform MethodDefinition → uni.Ability."""
        key = node.get("key", {})
        value = node.get("value", {})
        kind = node.get("kind", "method")

        if key.get("type") == "Identifier":
            name = self._make_name(key)
        else:
            name = self._make_name_from_str(
                kind if kind == "constructor" else "_computed", key
            )

        is_async = value.get("async", False)
        is_static = node.get("static", False)
        is_abstract = bool(node.get("abstract"))
        is_override = bool(node.get("override"))

        params = self._transform_params(value.get("params", []))
        return_type_ann = value.get("returnType")
        return_type_tag = self._make_type_tag(return_type_ann)

        sig_kids: list[uni.UniNode] = [
            *params,
            *([] if return_type_tag is None else [return_type_tag]),
        ]
        if not sig_kids:
            sig_kids = [self._make_token("LPAREN", "(", node)]

        sig = uni.FuncSignature(
            posonly_params=[],
            params=params,
            varargs=None,
            kwonlyargs=[],
            kwargs=None,
            return_type=return_type_tag.tag if return_type_tag else None,
            kid=sig_kids,
        )

        # Access modifier
        access_str = node.get("accessibility")
        access = None
        if access_str:
            acc_tok = self._make_token("ACCESS", access_str, node)
            access = uni.SubTag(tag=acc_tok, kid=[acc_tok])

        kids: list[uni.UniNode] = [name, sig]
        return uni.Ability(
            name_ref=name,
            is_async=is_async,
            is_override=is_override,
            is_static=is_static,
            is_abstract=is_abstract,
            access=access,
            signature=sig,
            body=None,
            kid=kids,
        )

    def _transform_PropertyDefinition(self, node: dict[str, Any]) -> uni.HasVar:
        """Transform PropertyDefinition → uni.HasVar."""
        key = node.get("key", {})
        if key.get("type") == "Identifier":
            name = self._make_name(key)
        else:
            name = self._make_name_from_str("_computed_prop", key)

        type_ann = node.get("typeAnnotation")
        type_tag = self._make_type_tag(type_ann)

        val_node = node.get("value")
        value = self._transform_expr(val_node) if val_node else None

        kids: list[uni.UniNode] = [name]
        if type_tag:
            kids.append(type_tag)
        if value:
            kids.append(value)

        return uni.HasVar(
            name=name,
            type_tag=type_tag,  # type: ignore[arg-type]
            value=value,
            defer=False,
            kid=kids,
        )

    # -------------------------------------------------------------------------
    # Interface declarations (TS-specific)
    # -------------------------------------------------------------------------

    def _transform_TSInterfaceDeclaration(self, node: dict[str, Any]) -> uni.Archetype:
        """Transform TSInterfaceDeclaration → uni.Archetype (interface)."""
        id_node = node.get("id", {})
        name = self._make_name(id_node)

        arch_type_tok = self._make_token("KW_OBJECT", "interface", node)

        # Extends
        extends = node.get("extends", [])
        base_classes: list[uni.Expr] = []
        for ext in extends:
            expr = ext.get("expression", {})
            if expr.get("type") == "Identifier":
                base_classes.append(self._make_name(expr))

        # Interface body
        body_node = node.get("body", {})
        members = body_node.get("body", [])
        body: list[uni.ArchBlockStmt] = []

        for member in members:
            result = self._transform_interface_member(member)
            if result:
                body.append(result)

        kids: list[uni.UniNode] = [name, arch_type_tok, *body]
        return uni.Archetype(
            name=name,
            arch_type=arch_type_tok,
            access=None,
            base_classes=base_classes if base_classes else None,
            body=body if body else None,
            kid=kids,
        )

    def _transform_interface_member(
        self, node: dict[str, Any]
    ) -> uni.ArchBlockStmt | None:
        """Transform an interface member to ArchHas (for properties) or Ability."""
        node_type = node.get("type", "")

        if node_type == "TSPropertySignature":
            has_var = self._transform_TSPropertySignature(node)
            return uni.ArchHas(
                is_static=False,
                access=None,
                vars=[has_var],
                is_frozen=False,
                kid=[has_var],
            )
        elif node_type == "TSMethodSignature":
            return self._transform_TSMethodSignature(node)
        elif node_type == "TSCallSignatureDeclaration":
            return None  # Skip call signatures
        elif node_type == "TSConstructSignatureDeclaration":
            return None  # Skip construct signatures
        elif node_type == "TSIndexSignature":
            return None  # Skip index signatures

        return None

    def _transform_TSPropertySignature(self, node: dict[str, Any]) -> uni.HasVar:
        """Transform TSPropertySignature → uni.HasVar."""
        key = node.get("key", {})
        if key.get("type") == "Identifier":
            name = self._make_name(key)
        else:
            name = self._make_name_from_str("_prop", key)

        type_ann = node.get("typeAnnotation")
        type_tag = self._make_type_tag(type_ann)

        kids: list[uni.UniNode] = [name]
        if type_tag:
            kids.append(type_tag)

        return uni.HasVar(
            name=name,
            type_tag=type_tag,  # type: ignore[arg-type]
            value=None,
            defer=False,
            kid=kids,
        )

    def _transform_TSMethodSignature(self, node: dict[str, Any]) -> uni.Ability:
        """Transform TSMethodSignature → uni.Ability."""
        key = node.get("key", {})
        if key.get("type") == "Identifier":
            name = self._make_name(key)
        else:
            name = self._make_name_from_str("_method", key)

        params = self._transform_params(node.get("params", []))
        return_type_ann = node.get("returnType")
        return_type_tag = self._make_type_tag(return_type_ann)

        sig_kids: list[uni.UniNode] = [
            *params,
            *([] if return_type_tag is None else [return_type_tag]),
        ]
        if not sig_kids:
            sig_kids = [self._make_token("LPAREN", "(", node)]

        sig = uni.FuncSignature(
            posonly_params=[],
            params=params,
            varargs=None,
            kwonlyargs=[],
            kwargs=None,
            return_type=return_type_tag.tag if return_type_tag else None,
            kid=sig_kids,
        )

        kids: list[uni.UniNode] = [name, sig]
        return uni.Ability(
            name_ref=name,
            is_async=False,
            is_override=False,
            is_static=False,
            is_abstract=False,
            access=None,
            signature=sig,
            body=None,
            kid=kids,
        )

    # -------------------------------------------------------------------------
    # Type alias declarations
    # -------------------------------------------------------------------------

    def _transform_TSTypeAliasDeclaration(self, node: dict[str, Any]) -> uni.GlobalVars:
        """Transform TSTypeAliasDeclaration → uni.GlobalVars (type alias as const)."""
        id_node = node.get("id", {})
        name = self._make_name(id_node)

        # Represent the type alias as a frozen variable with type annotation
        type_ann = node.get("typeAnnotation")
        type_tag = self._make_type_tag(
            {"type": "TSTypeAnnotation", "typeAnnotation": type_ann}
            if type_ann
            else None
        )

        kids: list[uni.UniNode] = [name]
        if type_tag:
            kids.append(type_tag)

        assignment = uni.Assignment(
            target=[name],
            value=None,
            type_tag=type_tag,
            kid=kids,
        )

        return uni.GlobalVars(
            access=None,
            assignments=[assignment],
            is_frozen=True,
            kid=[assignment],
        )

    # -------------------------------------------------------------------------
    # Enum declarations
    # -------------------------------------------------------------------------

    def _transform_TSEnumDeclaration(self, node: dict[str, Any]) -> uni.Enum:
        """Transform TSEnumDeclaration → uni.Enum."""
        id_node = node.get("id", {})
        name = self._make_name(id_node)

        members_raw = node.get("members", [])
        members: list[uni.Assignment] = []
        for member in members_raw:
            mem_id = member.get("id", {})
            if mem_id.get("type") == "Identifier":
                mem_name = self._make_name(mem_id)
            else:
                mem_name = self._make_name_from_str(
                    str(mem_id.get("value", "_")), mem_id
                )

            init = member.get("initializer")
            value = self._transform_expr(init) if init else None

            mem_kids: list[uni.UniNode] = [mem_name]
            if value:
                mem_kids.append(value)

            members.append(
                uni.Assignment(
                    target=[mem_name],
                    value=value,
                    type_tag=None,
                    kid=mem_kids,
                    is_enum_stmt=True,
                )
            )

        kids: list[uni.UniNode] = [name, *members]
        return uni.Enum(
            name=name,
            access=None,
            base_classes=[],
            body=cast(Sequence, members),
            kid=kids,
        )

    # -------------------------------------------------------------------------
    # Expression helpers (minimal — for default values and simple expressions)
    # -------------------------------------------------------------------------

    def _transform_expr(self, node: dict[str, Any] | None) -> uni.Expr | None:
        """Transform an ESTree expression into a uni.Name token (simplified).

        For type checking purposes, we represent expressions as Name tokens
        carrying their literal value. Full expression trees are not needed
        since we don't execute TS code.
        """
        if node is None:
            return None

        node_type = node.get("type", "")

        if node_type == "Identifier":
            return self._make_name(node)

        if node_type == "Literal":
            raw = node.get("raw", str(node.get("value", "")))
            return self._make_name_from_str(raw, node)

        if node_type in ("StringLiteral", "TemplateLiteral"):
            val = node.get("value", "")
            return self._make_name_from_str(f'"{val}"', node)

        if node_type in ("NumericLiteral", "NumberLiteral"):
            val = node.get("value", 0)
            return self._make_name_from_str(str(val), node)

        if node_type == "BooleanLiteral":
            val = node.get("value", False)
            return self._make_name_from_str(str(val), node)

        if node_type == "NullLiteral":
            return self._make_name_from_str("None", node)

        if node_type == "ArrayExpression":
            return self._make_name_from_str("[]", node)

        if node_type == "ObjectExpression":
            return self._make_name_from_str("{}", node)

        if node_type == "ArrowFunctionExpression":
            return self._make_name_from_str("lambda", node)

        if node_type == "FunctionExpression":
            return self._make_name_from_str("lambda", node)

        if node_type in ("CallExpression", "NewExpression"):
            callee = node.get("callee", {})
            if callee.get("type") == "Identifier":
                return self._make_name(callee)
            return self._make_name_from_str("_call", node)

        if node_type == "MemberExpression":
            obj = node.get("object", {})
            prop = node.get("property", {})
            obj_name = obj.get("name", "_")
            prop_name = prop.get("name", prop.get("value", "_"))
            return self._make_name_from_str(f"{obj_name}.{prop_name}", node)

        if node_type == "TSAsExpression":
            return self._transform_expr(node.get("expression"))

        if node_type == "UnaryExpression":
            arg = self._transform_expr(node.get("argument"))
            op = node.get("operator", "")
            if arg and isinstance(arg, uni.Name):
                return self._make_name_from_str(f"{op}{arg.value}", node)

        # Fallback: represent as a generic expression token
        return self._make_name_from_str("...", node)

    # -------------------------------------------------------------------------
    # Decorator helpers
    # -------------------------------------------------------------------------

    def _transform_decorators(
        self, decorators: list[dict[str, Any]]
    ) -> list[uni.Expr] | None:
        """Transform ESTree decorators list."""
        if not decorators:
            return None
        result: list[uni.Expr] = []
        for deco in decorators:
            expr = deco.get("expression", {})
            transformed = self._transform_expr(expr)
            if transformed:
                result.append(transformed)
        return result if result else None
