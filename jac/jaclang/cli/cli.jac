"""Command line interface tool for the Jac language.

This module provides the main CLI entry point and command implementations.
Commands are registered via the commands/ module using the new registry.
"""

import ast as ast3;
import marshal;
import os;
import pickle;
import sys;
import types;
import from importlib.metadata { version as pkg_version }
import from pathlib { Path }

# Import new registry infrastructure
import from jaclang.cli.registry { get_registry }
import from jaclang.cli.executor { get_executor }

# Import commands module to trigger auto-registration
import from jaclang.cli {
    commands
}

glob _runtime_initialized = False;

def _ensure_jac_runtime -> None;

#===============================================================================
# COMMAND DECLARATIONS (implementations in impl/cli.impl.jac)
# These are exported for use by commands/impl/ delegating implementations
#===============================================================================
def gen_parser -> str;

def format(paths: list, to_screen: bool = False, fix: bool = False) -> None;

def proc_file_sess(filename: str, session: str, <>root: (str | None) = None) -> tuple;

def run(
    filename: str, session: str = '', main: bool = True, cache: bool = True
) -> None;

def get_object(filename: str, id: str, session: str = '', main: bool = True) -> dict;

def build(filename: str, typecheck: bool = False) -> None;

def check(paths: list, print_errs: bool = True, warnonly: bool = False) -> None;

def lsp -> None;

def enter(
    filename: str,
    entrypoint: str,
    args: list,
    session: str = '',
    main: bool = True,
    <>root: str = '',
    <>node: str = ''
) -> None;

def <>test(
    filepath: str,
    test_name: str = '',
    filter: str = '',
    xit: bool = False,
    maxfail: int = None,
    directory: str = '',
    verbose: bool = False
) -> None;

def tool(tool: str, args: (list | None) = None) -> None;

def debug(filename: str, main: bool = True, cache: bool = False) -> None;

def dot(
    filename: str,
    session: str = '',
    initial: str = '',
    depth: int = -1,
    traverse: bool = False,
    connection: list[str] = [],
    bfs: bool = False,
    edge_limit: int = 512,
    node_limit: int = 512,
    saveto: str = '',
    to_screen: bool = False,
    format: str = 'dot'
) -> None;

def py2jac(filename: str) -> None;

def jac2py(filename: str) -> None;

def js(filename: str) -> None;

def serve(
    filename: str,
    session: str = '',
    port: int = 8000,
    main: bool = True,
    faux: bool = False
) -> None;

#===============================================================================
# PROJECT MANAGEMENT COMMANDS
#===============================================================================
def create(
    name: str = 'main', force: bool = False
) -> None;

def install(dev: bool = False, verbose: bool = False) -> None;

def add(
    packages: list = [],
    dev: bool = False,
    git: str = '',
    cl: bool = False,
    verbose: bool = False
) -> None;

def remove(packages: list = [], dev: bool = False, cl: bool = False) -> None;

def script(name: str = '', list_scripts: bool = False) -> None;

def plugins(action: str = 'list', names: list = [], verbose: bool = False) -> None;

def config(
    action: str = 'show',
    key: str = '',
    value: str = '',
    group: str = '',
    output: str = 'table'
) -> None;

#===============================================================================
# ENTRY POINT
#===============================================================================
def start_cli -> None;

with entry:__main__ {
    start_cli();
}
