"""Jac0Core - Bootstrap core modules for the Jac compiler.

This package contains the core Jac modules compiled by jac0 (the bootstrap
transpiler) during first-run setup. These modules form the compiler
infrastructure: AST definitions, passes, and compilation pipeline.

Only modules essential for bootstrapping the compiler belong here.
Runtime modules live in jaclang.runtimelib, native compilation support
in jaclang.compiler.native, and CLI modules in jaclang.cli.

Modules:
- unitree: Core AST definitions
- constant: Constants and token definitions
- codeinfo: Code location info and native layout metadata
- compiler: JacCompiler class (compilation singleton)
- program: JacProgram class (program state)
- passes/: Bootstrap-critical compiler passes
- parser/: Recursive descent parser
- helpers: Utility functions
- log: Logging utilities
- modresolver: Module resolution utilities
- treeprinter: AST tree printing utilities
- bccache: Bytecode cache discovery
- compile_options: Compiler options
- mtp: Meaning-typed programming IR
- jir: JIR serialization format
- jir_registry: JIR node registry
- jir_passes: JIR reader/writer passes
- interop_bridge: Native interop bridge
"""
