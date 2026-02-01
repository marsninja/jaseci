"""Tests for the ESTree-based TypeScript/JavaScript parser (oxc-parser)."""

import os
import shutil
import unittest

import jaclang.pycore.unitree as uni
from jaclang.pycore.estree_transformer import EsTreeToUniAst

# Test fixture paths
FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "typescript")

# Check if a JS runtime is available for integration tests
_HAS_JS_RUNTIME = shutil.which("bun") is not None or shutil.which("node") is not None


def _make_source(code: str = "", path: str = "test.ts") -> uni.Source:
    """Create a uni.Source for testing."""
    return uni.Source(code, mod_path=path)


# =====================================================================
# Unit tests for ESTree transformer (no JS runtime needed)
# =====================================================================


class TestEsTreeTransformer(unittest.TestCase):
    """Test the ESTree JSON → uni.* AST transformer."""

    def setUp(self) -> None:
        self.source = _make_source("", "test.ts")
        self.transformer = EsTreeToUniAst(source=self.source, file_path="test.ts")

    def test_empty_program(self) -> None:
        """Empty program produces empty module."""
        estree = {"program": {"type": "Program", "body": []}}
        mod = self.transformer.transform(estree)
        self.assertIsInstance(mod, uni.Module)
        self.assertEqual(mod.name, "test")
        self.assertEqual(len(mod.body), 0)

    def test_variable_declaration_const(self) -> None:
        """const declaration → GlobalVars(is_frozen=True)."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "VariableDeclaration",
                        "kind": "const",
                        "declarations": [
                            {
                                "type": "VariableDeclarator",
                                "id": {
                                    "type": "Identifier",
                                    "name": "API_URL",
                                    "loc": {
                                        "start": {"line": 1, "column": 6},
                                        "end": {"line": 1, "column": 13},
                                    },
                                    "range": [6, 13],
                                    "typeAnnotation": {
                                        "type": "TSTypeAnnotation",
                                        "typeAnnotation": {
                                            "type": "TSStringKeyword",
                                            "loc": {
                                                "start": {"line": 1, "column": 15},
                                                "end": {"line": 1, "column": 21},
                                            },
                                            "range": [15, 21],
                                        },
                                    },
                                },
                                "init": {
                                    "type": "Literal",
                                    "value": "https://api.example.com",
                                    "raw": '"https://api.example.com"',
                                    "loc": {
                                        "start": {"line": 1, "column": 24},
                                        "end": {"line": 1, "column": 49},
                                    },
                                    "range": [24, 49],
                                },
                                "loc": {
                                    "start": {"line": 1, "column": 6},
                                    "end": {"line": 1, "column": 49},
                                },
                                "range": [6, 49],
                            }
                        ],
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 1, "column": 50},
                        },
                        "range": [0, 50],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        self.assertEqual(len(mod.body), 1)
        gv = mod.body[0]
        self.assertIsInstance(gv, uni.GlobalVars)
        assert isinstance(gv, uni.GlobalVars)
        self.assertTrue(gv.is_frozen)
        self.assertEqual(len(gv.assignments), 1)

        assign = gv.assignments[0]
        # Target should be Name directly (not AtomTrailer)
        self.assertIsInstance(assign.target[0], uni.Name)
        assert isinstance(assign.target[0], uni.Name)
        self.assertEqual(assign.target[0].value, "API_URL")
        self.assertIsNotNone(assign.type_tag)
        assert assign.type_tag is not None
        assert isinstance(assign.type_tag.tag, uni.Token)
        self.assertEqual(assign.type_tag.tag.value, "str")

    def test_function_declaration(self) -> None:
        """FunctionDeclaration → Ability with params and return type."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "FunctionDeclaration",
                        "id": {
                            "type": "Identifier",
                            "name": "greet",
                            "loc": {
                                "start": {"line": 1, "column": 9},
                                "end": {"line": 1, "column": 14},
                            },
                            "range": [9, 14],
                        },
                        "async": False,
                        "params": [
                            {
                                "type": "Identifier",
                                "name": "name",
                                "typeAnnotation": {
                                    "type": "TSTypeAnnotation",
                                    "typeAnnotation": {
                                        "type": "TSStringKeyword",
                                        "loc": {
                                            "start": {"line": 1, "column": 21},
                                            "end": {"line": 1, "column": 27},
                                        },
                                        "range": [21, 27],
                                    },
                                },
                                "loc": {
                                    "start": {"line": 1, "column": 15},
                                    "end": {"line": 1, "column": 27},
                                },
                                "range": [15, 27],
                            }
                        ],
                        "returnType": {
                            "type": "TSTypeAnnotation",
                            "typeAnnotation": {
                                "type": "TSStringKeyword",
                                "loc": {
                                    "start": {"line": 1, "column": 30},
                                    "end": {"line": 1, "column": 36},
                                },
                                "range": [30, 36],
                            },
                        },
                        "body": {"type": "BlockStatement", "body": []},
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 1, "column": 40},
                        },
                        "range": [0, 40],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        self.assertEqual(len(mod.body), 1)
        ability = mod.body[0]
        self.assertIsInstance(ability, uni.Ability)
        assert isinstance(ability, uni.Ability)
        assert isinstance(ability.name_ref, uni.Name)
        self.assertEqual(ability.name_ref.value, "greet")
        self.assertFalse(ability.is_async)
        self.assertIsNotNone(ability.signature)
        assert isinstance(ability.signature, uni.FuncSignature)
        self.assertEqual(len(ability.signature.params), 1)
        self.assertEqual(ability.signature.params[0].name.value, "name")

    def test_interface_declaration(self) -> None:
        """TSInterfaceDeclaration → Archetype with HasVar members."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "TSInterfaceDeclaration",
                        "id": {
                            "type": "Identifier",
                            "name": "Todo",
                            "loc": {
                                "start": {"line": 1, "column": 10},
                                "end": {"line": 1, "column": 14},
                            },
                            "range": [10, 14],
                        },
                        "body": {
                            "type": "TSInterfaceBody",
                            "body": [
                                {
                                    "type": "TSPropertySignature",
                                    "key": {
                                        "type": "Identifier",
                                        "name": "id",
                                        "loc": {
                                            "start": {"line": 2, "column": 2},
                                            "end": {"line": 2, "column": 4},
                                        },
                                        "range": [18, 20],
                                    },
                                    "typeAnnotation": {
                                        "type": "TSTypeAnnotation",
                                        "typeAnnotation": {
                                            "type": "TSNumberKeyword",
                                            "loc": {
                                                "start": {"line": 2, "column": 6},
                                                "end": {"line": 2, "column": 12},
                                            },
                                            "range": [22, 28],
                                        },
                                    },
                                    "loc": {
                                        "start": {"line": 2, "column": 2},
                                        "end": {"line": 2, "column": 13},
                                    },
                                    "range": [18, 29],
                                },
                                {
                                    "type": "TSPropertySignature",
                                    "key": {
                                        "type": "Identifier",
                                        "name": "title",
                                        "loc": {
                                            "start": {"line": 3, "column": 2},
                                            "end": {"line": 3, "column": 7},
                                        },
                                        "range": [32, 37],
                                    },
                                    "typeAnnotation": {
                                        "type": "TSTypeAnnotation",
                                        "typeAnnotation": {
                                            "type": "TSStringKeyword",
                                            "loc": {
                                                "start": {"line": 3, "column": 9},
                                                "end": {"line": 3, "column": 15},
                                            },
                                            "range": [39, 45],
                                        },
                                    },
                                    "loc": {
                                        "start": {"line": 3, "column": 2},
                                        "end": {"line": 3, "column": 16},
                                    },
                                    "range": [32, 46],
                                },
                            ],
                        },
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 4, "column": 1},
                        },
                        "range": [0, 48],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        self.assertEqual(len(mod.body), 1)
        arch = mod.body[0]
        self.assertIsInstance(arch, uni.Archetype)
        assert isinstance(arch, uni.Archetype)
        self.assertEqual(arch.name.value, "Todo")
        self.assertIsNotNone(arch.body)
        assert arch.body is not None
        body = list(arch.body)
        self.assertEqual(len(body), 2)

        arch_has1 = body[0]
        self.assertIsInstance(arch_has1, uni.ArchHas)
        assert isinstance(arch_has1, uni.ArchHas)
        self.assertEqual(len(arch_has1.vars), 1)
        prop1 = arch_has1.vars[0]
        self.assertIsInstance(prop1, uni.HasVar)
        assert isinstance(prop1, uni.HasVar)
        self.assertEqual(prop1.name.value, "id")
        self.assertIsNotNone(prop1.type_tag)
        assert prop1.type_tag is not None
        assert isinstance(prop1.type_tag.tag, uni.Token)
        self.assertEqual(prop1.type_tag.tag.value, "float")

        arch_has2 = body[1]
        self.assertIsInstance(arch_has2, uni.ArchHas)
        assert isinstance(arch_has2, uni.ArchHas)
        prop2 = arch_has2.vars[0]
        assert isinstance(prop2, uni.HasVar)
        self.assertEqual(prop2.name.value, "title")
        assert prop2.type_tag is not None
        assert isinstance(prop2.type_tag.tag, uni.Token)
        self.assertEqual(prop2.type_tag.tag.value, "str")

    def test_enum_declaration(self) -> None:
        """TSEnumDeclaration → Enum with members."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "TSEnumDeclaration",
                        "id": {
                            "type": "Identifier",
                            "name": "Priority",
                            "loc": {
                                "start": {"line": 1, "column": 5},
                                "end": {"line": 1, "column": 13},
                            },
                            "range": [5, 13],
                        },
                        "members": [
                            {
                                "type": "TSEnumMember",
                                "id": {
                                    "type": "Identifier",
                                    "name": "LOW",
                                    "loc": {
                                        "start": {"line": 2, "column": 2},
                                        "end": {"line": 2, "column": 5},
                                    },
                                    "range": [18, 21],
                                },
                                "initializer": {
                                    "type": "Literal",
                                    "value": 0,
                                    "raw": "0",
                                    "loc": {
                                        "start": {"line": 2, "column": 8},
                                        "end": {"line": 2, "column": 9},
                                    },
                                    "range": [24, 25],
                                },
                            },
                            {
                                "type": "TSEnumMember",
                                "id": {
                                    "type": "Identifier",
                                    "name": "HIGH",
                                    "loc": {
                                        "start": {"line": 3, "column": 2},
                                        "end": {"line": 3, "column": 6},
                                    },
                                    "range": [29, 33],
                                },
                                "initializer": {
                                    "type": "Literal",
                                    "value": 2,
                                    "raw": "2",
                                    "loc": {
                                        "start": {"line": 3, "column": 9},
                                        "end": {"line": 3, "column": 10},
                                    },
                                    "range": [36, 37],
                                },
                            },
                        ],
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 4, "column": 1},
                        },
                        "range": [0, 39],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        self.assertEqual(len(mod.body), 1)
        enum = mod.body[0]
        self.assertIsInstance(enum, uni.Enum)
        assert isinstance(enum, uni.Enum)
        self.assertEqual(enum.name.value, "Priority")
        assert enum.body is not None
        self.assertEqual(len(list(enum.body)), 2)

    def test_import_declaration(self) -> None:
        """ImportDeclaration → Import with ModulePath and ModuleItems."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "ImportDeclaration",
                        "source": {
                            "type": "Literal",
                            "value": "react",
                            "loc": {
                                "start": {"line": 1, "column": 35},
                                "end": {"line": 1, "column": 42},
                            },
                            "range": [35, 42],
                        },
                        "specifiers": [
                            {
                                "type": "ImportSpecifier",
                                "imported": {
                                    "type": "Identifier",
                                    "name": "useState",
                                    "loc": {
                                        "start": {"line": 1, "column": 9},
                                        "end": {"line": 1, "column": 17},
                                    },
                                    "range": [9, 17],
                                },
                                "local": {
                                    "type": "Identifier",
                                    "name": "useState",
                                    "loc": {
                                        "start": {"line": 1, "column": 9},
                                        "end": {"line": 1, "column": 17},
                                    },
                                    "range": [9, 17],
                                },
                            },
                            {
                                "type": "ImportSpecifier",
                                "imported": {
                                    "type": "Identifier",
                                    "name": "useEffect",
                                    "loc": {
                                        "start": {"line": 1, "column": 19},
                                        "end": {"line": 1, "column": 28},
                                    },
                                    "range": [19, 28],
                                },
                                "local": {
                                    "type": "Identifier",
                                    "name": "useEffect",
                                    "loc": {
                                        "start": {"line": 1, "column": 19},
                                        "end": {"line": 1, "column": 28},
                                    },
                                    "range": [19, 28],
                                },
                            },
                        ],
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 1, "column": 43},
                        },
                        "range": [0, 43],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        self.assertEqual(len(mod.body), 1)
        imp = mod.body[0]
        self.assertIsInstance(imp, uni.Import)
        assert isinstance(imp, uni.Import)
        self.assertIsNotNone(imp.from_loc)
        assert imp.from_loc is not None
        self.assertEqual(len(imp.items), 2)

        item0 = imp.items[0]
        assert isinstance(item0, uni.ModuleItem)
        self.assertEqual(item0.name.value, "useState")
        self.assertIsNone(item0.alias)

    def test_class_declaration(self) -> None:
        """ClassDeclaration → Archetype with methods and properties."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "ClassDeclaration",
                        "id": {
                            "type": "Identifier",
                            "name": "MyClass",
                            "loc": {
                                "start": {"line": 1, "column": 6},
                                "end": {"line": 1, "column": 13},
                            },
                            "range": [6, 13],
                        },
                        "body": {
                            "type": "ClassBody",
                            "body": [
                                {
                                    "type": "PropertyDefinition",
                                    "key": {
                                        "type": "Identifier",
                                        "name": "count",
                                        "loc": {
                                            "start": {"line": 2, "column": 2},
                                            "end": {"line": 2, "column": 7},
                                        },
                                        "range": [18, 23],
                                    },
                                    "typeAnnotation": {
                                        "type": "TSTypeAnnotation",
                                        "typeAnnotation": {
                                            "type": "TSNumberKeyword",
                                            "loc": {
                                                "start": {"line": 2, "column": 9},
                                                "end": {"line": 2, "column": 15},
                                            },
                                            "range": [25, 31],
                                        },
                                    },
                                    "value": None,
                                    "loc": {
                                        "start": {"line": 2, "column": 2},
                                        "end": {"line": 2, "column": 16},
                                    },
                                    "range": [18, 32],
                                },
                                {
                                    "type": "MethodDefinition",
                                    "kind": "method",
                                    "key": {
                                        "type": "Identifier",
                                        "name": "increment",
                                        "loc": {
                                            "start": {"line": 3, "column": 2},
                                            "end": {"line": 3, "column": 11},
                                        },
                                        "range": [35, 44],
                                    },
                                    "value": {
                                        "type": "FunctionExpression",
                                        "async": False,
                                        "params": [],
                                        "returnType": {
                                            "type": "TSTypeAnnotation",
                                            "typeAnnotation": {
                                                "type": "TSVoidKeyword",
                                                "loc": {
                                                    "start": {"line": 3, "column": 15},
                                                    "end": {"line": 3, "column": 19},
                                                },
                                                "range": [48, 52],
                                            },
                                        },
                                    },
                                    "static": False,
                                    "loc": {
                                        "start": {"line": 3, "column": 2},
                                        "end": {"line": 3, "column": 25},
                                    },
                                    "range": [35, 58],
                                },
                            ],
                        },
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 4, "column": 1},
                        },
                        "range": [0, 60],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        self.assertEqual(len(mod.body), 1)
        arch = mod.body[0]
        self.assertIsInstance(arch, uni.Archetype)
        assert isinstance(arch, uni.Archetype)
        self.assertEqual(arch.name.value, "MyClass")
        assert arch.body is not None
        body = list(arch.body)
        self.assertEqual(len(body), 2)
        self.assertIsInstance(body[0], uni.ArchHas)
        assert isinstance(body[0], uni.ArchHas)
        self.assertIsInstance(body[0].vars[0], uni.HasVar)
        self.assertIsInstance(body[1], uni.Ability)

    def test_source_locations_preserved(self) -> None:
        """Verify source locations from ESTree are preserved in uni.Name nodes."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "FunctionDeclaration",
                        "id": {
                            "type": "Identifier",
                            "name": "myFunc",
                            "loc": {
                                "start": {"line": 5, "column": 9},
                                "end": {"line": 5, "column": 15},
                            },
                            "range": [42, 48],
                        },
                        "async": False,
                        "params": [],
                        "body": {"type": "BlockStatement", "body": []},
                        "loc": {
                            "start": {"line": 5, "column": 0},
                            "end": {"line": 5, "column": 20},
                        },
                        "range": [33, 53],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        ability = mod.body[0]
        assert isinstance(ability, uni.Ability)
        name = ability.name_ref
        assert isinstance(name, uni.Name)
        self.assertEqual(name.value, "myFunc")
        self.assertEqual(name.line_no, 5)
        self.assertEqual(name.c_start, 9)
        self.assertEqual(name.pos_start, 42)
        self.assertEqual(name.pos_end, 48)

    def test_export_named_passes_through_declaration(self) -> None:
        """ExportNamedDeclaration passes through to the inner declaration."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "ExportNamedDeclaration",
                        "declaration": {
                            "type": "FunctionDeclaration",
                            "id": {
                                "type": "Identifier",
                                "name": "exported",
                                "loc": {
                                    "start": {"line": 1, "column": 16},
                                    "end": {"line": 1, "column": 24},
                                },
                                "range": [16, 24],
                            },
                            "async": True,
                            "params": [],
                            "body": {"type": "BlockStatement", "body": []},
                            "loc": {
                                "start": {"line": 1, "column": 7},
                                "end": {"line": 1, "column": 30},
                            },
                            "range": [7, 30],
                        },
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 1, "column": 30},
                        },
                        "range": [0, 30],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        self.assertEqual(len(mod.body), 1)
        ability = mod.body[0]
        self.assertIsInstance(ability, uni.Ability)
        assert isinstance(ability, uni.Ability)
        assert isinstance(ability.name_ref, uni.Name)
        self.assertEqual(ability.name_ref.value, "exported")
        self.assertTrue(ability.is_async)

    def test_symtab_build_pass_on_ts_module(self) -> None:
        """Verify SymTabBuildPass correctly builds symbols from TS AST."""
        from jaclang.pycore.passes.sym_tab_build_pass import SymTabBuildPass
        from jaclang.pycore.program import JacProgram

        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "VariableDeclaration",
                        "kind": "const",
                        "declarations": [
                            {
                                "type": "VariableDeclarator",
                                "id": {
                                    "type": "Identifier",
                                    "name": "MY_CONST",
                                    "loc": {
                                        "start": {"line": 1, "column": 6},
                                        "end": {"line": 1, "column": 14},
                                    },
                                    "range": [6, 14],
                                },
                                "init": None,
                                "loc": {
                                    "start": {"line": 1, "column": 6},
                                    "end": {"line": 1, "column": 14},
                                },
                                "range": [6, 14],
                            }
                        ],
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 1, "column": 15},
                        },
                        "range": [0, 15],
                    },
                    {
                        "type": "FunctionDeclaration",
                        "id": {
                            "type": "Identifier",
                            "name": "myFunc",
                            "loc": {
                                "start": {"line": 2, "column": 9},
                                "end": {"line": 2, "column": 15},
                            },
                            "range": [16, 22],
                        },
                        "async": False,
                        "params": [
                            {
                                "type": "Identifier",
                                "name": "x",
                                "loc": {
                                    "start": {"line": 2, "column": 16},
                                    "end": {"line": 2, "column": 17},
                                },
                                "range": [23, 24],
                            }
                        ],
                        "body": {"type": "BlockStatement", "body": []},
                        "loc": {
                            "start": {"line": 2, "column": 0},
                            "end": {"line": 2, "column": 20},
                        },
                        "range": [16, 36],
                    },
                    {
                        "type": "ClassDeclaration",
                        "id": {
                            "type": "Identifier",
                            "name": "MyClass",
                            "loc": {
                                "start": {"line": 3, "column": 6},
                                "end": {"line": 3, "column": 13},
                            },
                            "range": [37, 44],
                        },
                        "body": {
                            "type": "ClassBody",
                            "body": [
                                {
                                    "type": "PropertyDefinition",
                                    "key": {
                                        "type": "Identifier",
                                        "name": "value",
                                        "loc": {
                                            "start": {"line": 4, "column": 2},
                                            "end": {"line": 4, "column": 7},
                                        },
                                        "range": [48, 53],
                                    },
                                    "typeAnnotation": {
                                        "type": "TSTypeAnnotation",
                                        "typeAnnotation": {
                                            "type": "TSNumberKeyword",
                                            "loc": {
                                                "start": {"line": 4, "column": 9},
                                                "end": {"line": 4, "column": 15},
                                            },
                                            "range": [55, 61],
                                        },
                                    },
                                    "value": None,
                                    "static": False,
                                    "loc": {
                                        "start": {"line": 4, "column": 2},
                                        "end": {"line": 4, "column": 16},
                                    },
                                    "range": [48, 62],
                                }
                            ],
                        },
                        "loc": {
                            "start": {"line": 3, "column": 0},
                            "end": {"line": 5, "column": 1},
                        },
                        "range": [37, 64],
                    },
                ],
            }
        }
        mod = self.transformer.transform(estree)

        # Run SymTabBuildPass
        prog = JacProgram()
        prog.mod = uni.ProgramModule(mod)
        prog.mod.hub[mod.loc.mod_path] = mod
        SymTabBuildPass(ir_in=mod, prog=prog)

        # Check symbols were registered at module scope
        sym_names = set(mod.names_in_scope.keys())
        self.assertIn("MY_CONST", sym_names, f"Available: {sym_names}")
        self.assertIn("myFunc", sym_names, f"Available: {sym_names}")
        self.assertIn("MyClass", sym_names, f"Available: {sym_names}")

        # Check class member symbol (value) is in MyClass scope
        my_class = None
        for stmt in mod.body:
            if isinstance(stmt, uni.Archetype) and stmt.name.value == "MyClass":
                my_class = stmt
                break
        self.assertIsNotNone(my_class)
        assert my_class is not None
        class_sym_names = set(my_class.names_in_scope.keys())
        self.assertIn("value", class_sym_names, f"Available: {class_sym_names}")

    def test_type_alias(self) -> None:
        """TSTypeAliasDeclaration → GlobalVars."""
        estree = {
            "program": {
                "type": "Program",
                "body": [
                    {
                        "type": "TSTypeAliasDeclaration",
                        "id": {
                            "type": "Identifier",
                            "name": "Status",
                            "loc": {
                                "start": {"line": 1, "column": 5},
                                "end": {"line": 1, "column": 11},
                            },
                            "range": [5, 11],
                        },
                        "typeAnnotation": {
                            "type": "TSUnionType",
                            "types": [
                                {
                                    "type": "TSLiteralType",
                                    "literal": {
                                        "type": "StringLiteral",
                                        "value": "active",
                                        "raw": '"active"',
                                    },
                                    "loc": {
                                        "start": {"line": 1, "column": 14},
                                        "end": {"line": 1, "column": 22},
                                    },
                                    "range": [14, 22],
                                },
                                {
                                    "type": "TSLiteralType",
                                    "literal": {
                                        "type": "StringLiteral",
                                        "value": "done",
                                        "raw": '"done"',
                                    },
                                    "loc": {
                                        "start": {"line": 1, "column": 25},
                                        "end": {"line": 1, "column": 31},
                                    },
                                    "range": [25, 31],
                                },
                            ],
                            "loc": {
                                "start": {"line": 1, "column": 14},
                                "end": {"line": 1, "column": 31},
                            },
                            "range": [14, 31],
                        },
                        "loc": {
                            "start": {"line": 1, "column": 0},
                            "end": {"line": 1, "column": 32},
                        },
                        "range": [0, 32],
                    }
                ],
            }
        }
        mod = self.transformer.transform(estree)
        self.assertEqual(len(mod.body), 1)
        gv = mod.body[0]
        self.assertIsInstance(gv, uni.GlobalVars)
        assert isinstance(gv, uni.GlobalVars)
        self.assertTrue(gv.is_frozen)


# =====================================================================
# Integration tests (require bun/node + oxc-parser)
# =====================================================================


@unittest.skipUnless(_HAS_JS_RUNTIME, "No JavaScript runtime (bun/node) available")
class TestEsTreeParserIntegration(unittest.TestCase):
    """Integration tests that use the real oxc-parser subprocess."""

    _deps_available: bool = False

    @classmethod
    def setUpClass(cls) -> None:
        """Ensure dependencies are installed."""
        from jaclang.pycore.estree_parser import _ensure_deps

        try:
            _ensure_deps()
            cls._deps_available = True
        except Exception:
            cls._deps_available = False

    def test_parse_basic_fixture(self) -> None:
        """Parse basic.ts fixture file end-to-end."""
        if not self._deps_available:
            self.skipTest("oxc-parser not installed")

        from jaclang.pycore.estree_parser import parse_ts_to_estree

        fixture = os.path.join(FIXTURE_DIR, "basic.ts")
        if not os.path.exists(fixture):
            self.skipTest("basic.ts fixture not found")

        estree = parse_ts_to_estree(fixture)
        self.assertIn("program", estree)
        self.assertIn("body", estree["program"])
        body = estree["program"]["body"]
        self.assertTrue(len(body) > 0)

    def test_parse_and_transform_basic(self) -> None:
        """Parse basic.ts and transform to uni.Module."""
        if not self._deps_available:
            self.skipTest("oxc-parser not installed")

        from jaclang.pycore.estree_parser import parse_ts_file

        fixture = os.path.join(FIXTURE_DIR, "basic.ts")
        if not os.path.exists(fixture):
            self.skipTest("basic.ts fixture not found")

        with open(fixture) as f:
            source_str = f.read()

        source = uni.Source(source_str, mod_path=fixture)
        mod = parse_ts_file(fixture, source_str, source)

        self.assertIsInstance(mod, uni.Module)
        self.assertFalse(mod.has_syntax_errors)

        # Should contain functions, interfaces, classes, enums
        has_ability = any(isinstance(n, uni.Ability) for n in mod.body)
        has_archetype = any(isinstance(n, uni.Archetype) for n in mod.body)
        has_enum = any(isinstance(n, uni.Enum) for n in mod.body)
        self.assertTrue(has_ability, "Should have at least one function/ability")
        self.assertTrue(has_archetype, "Should have at least one class/interface")
        self.assertTrue(has_enum, "Should have at least one enum")

    def test_parse_imports_fixture(self) -> None:
        """Parse imports.ts and verify import nodes."""
        if not self._deps_available:
            self.skipTest("oxc-parser not installed")

        from jaclang.pycore.estree_parser import parse_ts_file

        fixture = os.path.join(FIXTURE_DIR, "imports.ts")
        if not os.path.exists(fixture):
            self.skipTest("imports.ts fixture not found")

        with open(fixture) as f:
            source_str = f.read()

        source = uni.Source(source_str, mod_path=fixture)
        mod = parse_ts_file(fixture, source_str, source)

        imports = [n for n in mod.body if isinstance(n, uni.Import)]
        self.assertTrue(len(imports) > 0, "Should have at least one import")

    def test_parse_inline_source(self) -> None:
        """Parse inline TypeScript source string."""
        if not self._deps_available:
            self.skipTest("oxc-parser not installed")

        from jaclang.pycore.estree_parser import parse_ts_file

        code = "export const x: number = 42;"
        source = uni.Source(code, mod_path="inline.ts")
        mod = parse_ts_file("inline.ts", code, source)

        self.assertIsInstance(mod, uni.Module)
        self.assertEqual(len(mod.body), 1)
        self.assertIsInstance(mod.body[0], uni.GlobalVars)

    def test_parse_server_lifecycle(self) -> None:
        """Start, use, and stop the persistent parse server."""
        if not self._deps_available:
            self.skipTest("oxc-parser not installed")

        from jaclang.pycore.estree_parser import TsParseServer

        server = TsParseServer()
        try:
            result = server.parse(
                "test.ts", source="export interface Foo { bar: string; }"
            )
            self.assertIn("program", result)
            body = result["program"]["body"]
            self.assertTrue(len(body) > 0)
        finally:
            server.stop()

    def test_ts_module_symbols_after_compilation(self) -> None:
        """Compile basic.ts with symtab_ir_only and verify symbols in scope."""
        if not self._deps_available:
            self.skipTest("oxc-parser not installed")

        from jaclang.pycore.estree_parser import parse_ts_file
        from jaclang.pycore.passes.def_impl_match_pass import DeclImplMatchPass
        from jaclang.pycore.passes.sym_tab_build_pass import SymTabBuildPass
        from jaclang.pycore.program import JacProgram

        fixture = os.path.join(FIXTURE_DIR, "basic.ts")
        if not os.path.exists(fixture):
            self.skipTest("basic.ts fixture not found")

        with open(fixture) as f:
            source_str = f.read()

        source = uni.Source(source_str, mod_path=fixture)
        mod = parse_ts_file(fixture, source_str, source)

        self.assertIsInstance(mod, uni.Module)
        self.assertFalse(mod.has_syntax_errors)

        # Run the symtab passes (same schedule as symtab_ir_only)
        prog = JacProgram()
        prog.mod = uni.ProgramModule(mod)
        prog.mod.hub[fixture] = mod
        SymTabBuildPass(ir_in=mod, prog=prog)
        DeclImplMatchPass(ir_in=mod, prog=prog)

        # Verify expected symbols from basic.ts are in module scope
        sym_names = set(mod.names_in_scope.keys())
        expected = {
            "API_URL",
            "count",
            "legacy",
            "greet",
            "fetchData",
            "Todo",
            "TodoService",
            "TodoApp",
            "Status",
            "Priority",
        }
        for name in expected:
            self.assertIn(
                name,
                sym_names,
                f"'{name}' not found in TS module scope. Available: {sym_names}",
            )


if __name__ == "__main__":
    unittest.main()
