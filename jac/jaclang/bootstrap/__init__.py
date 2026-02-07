"""Jac Bootstrap Compiler.

Three-layer bootstrap chain for the Jac compiler:

  Layer 0 (seed_compiler.py) — Python seed that compiles a Jac subset
  Layer 1 (.jac files)       — Bootstrap compiler written in Jac Layer 0 subset
  Layer 2                    — Full Jac compiler (future)

Layer 1 modules (compiled by the seed at import time):
  bootstrap_ast      — AST node definitions
  bootstrap_lexer    — Tokenizer
  bootstrap_parser   — Recursive-descent parser
  bootstrap_codegen  — Python source code generator
  bootstrap_symtab   — Symbol table and impl matching
  bootstrap_compiler — Full pipeline orchestration with bytecode caching

Public API:
  seed_compile(source, filename) — Compile Jac source via the seed compiler
  seed_compile_file(path)        — Compile a Jac file via the seed compiler
  seed_exec(source, filename)    — Compile and execute Jac source via the seed
"""

from jaclang.bootstrap.seed_compiler import (
    seed_compile,
    seed_compile_file,
    seed_exec,
)

__all__ = [
    "seed_compile",
    "seed_compile_file",
    "seed_exec",
]
