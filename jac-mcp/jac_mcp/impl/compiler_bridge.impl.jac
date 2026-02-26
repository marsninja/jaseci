"""Implementation of compiler bridge."""

import from typing { Any }
import tempfile;
import os;
import threading;
import io;
import sys;

"""Run a function with timeout protection."""
impl run_with_timeout(func: object, timeout: int = 10) -> tuple {
    result_holder: list = [None];
    error_holder: list = [None];
    def _worker -> None {
        try {
            result_holder[0] = func();
        } except Exception as e {
            error_holder[0] = e;
        }
    }
    t = threading.Thread(target=_worker);
    t.start();
    t.join(timeout=timeout);
    if t.is_alive() {
        return (False, "Operation timed out");
    }
    if error_holder[0] is not None {
        return (False, str(error_holder[0]));
    }
    return (True, result_holder[0]);
}

"""Parse Jac code and return structured errors."""
impl CompilerBridge.parse_snippet(
    code: str, filename: str = "snippet.jac"
) -> dict[str, Any] {
    if len(code) > MAX_INPUT_SIZE {
        return {
            "valid": False,
            "errors": [
                {
                    "line": 0,
                    "col": 0,
                    "message": f"Input exceeds maximum size of {MAX_INPUT_SIZE} bytes"
                }
            ]
        };
    }
    def _do_parse -> dict[str, Any] {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        import from jaclang.jac0core.program { JacProgram }

        Jac.setup();

        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as f {
            f.write(code);
            tmp_path = f.name;
        }

        try {
            program = JacProgram();
            compiler = Jac.get_compiler();

            old_stderr = sys.stderr;
            captured = io.StringIO();
            sys.stderr = captured;

            try {
                ir = compiler.compile(tmp_path, program);
            } finally {
                sys.stderr = old_stderr;
            }

            errors: list[dict] = [];
            stderr_output = captured.getvalue();
            if stderr_output.strip() {
                for line in stderr_output.strip().split("\n") {
                    if line.strip() {
                        errors.append({"line": 0, "col": 0, "message": line.strip()});
                    }
                }
            }

            valid = len(errors) == 0 and ir is not None;
            return {"valid": valid, "errors": errors};
        } finally {
            os.unlink(tmp_path);
        }
    }
    (success, result) = run_with_timeout(_do_parse);
    if not success {
        return {
            "valid": False,
            "errors": [{"line": 0, "col": 0, "message": str(result)}]
        };
    }
    return result;
}

"""Full type-check pipeline on Jac code."""
impl CompilerBridge.typecheck_snippet(
    code: str, filename: str = "snippet.jac"
) -> dict[str, Any] {
    if len(code) > MAX_INPUT_SIZE {
        return {
            "valid": False,
            "errors": [
                {
                    "line": 0,
                    "col": 0,
                    "message": f"Input exceeds maximum size of {MAX_INPUT_SIZE} bytes"
                }
            ],
            "warnings": []
        };
    }
    def _do_typecheck -> dict[str, Any] {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        import from jaclang.jac0core.program { JacProgram }

        Jac.setup();

        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as f {
            f.write(code);
            tmp_path = f.name;
        }

        try {
            program = JacProgram();
            compiler = Jac.get_compiler();

            old_stderr = sys.stderr;
            captured = io.StringIO();
            sys.stderr = captured;

            try {
                ir = compiler.compile(tmp_path, program);
            } finally {
                sys.stderr = old_stderr;
            }

            errors: list[dict] = [];
            warnings: list[dict] = [];
            stderr_output = captured.getvalue();
            if stderr_output.strip() {
                for line in stderr_output.strip().split("\n") {
                    line = line.strip();
                    if "warning" in line.lower() {
                        warnings.append({"line": 0, "col": 0, "message": line});
                    } elif line {
                        errors.append({"line": 0, "col": 0, "message": line});
                    }
                }
            }

            valid = len(errors) == 0 and ir is not None;
            return {"valid": valid, "errors": errors, "warnings": warnings};
        } finally {
            os.unlink(tmp_path);
        }
    }
    (success, result) = run_with_timeout(_do_typecheck);
    if not success {
        return {
            "valid": False,
            "errors": [{"line": 0, "col": 0, "message": str(result)}],
            "warnings": []
        };
    }
    return result;
}

"""Format Jac code."""
impl CompilerBridge.format_snippet(code: str) -> dict[str, Any] {
    if len(code) > MAX_INPUT_SIZE {
        return {
            "formatted": code,
            "changed": False,
            "error": f"Input exceeds maximum size of {MAX_INPUT_SIZE} bytes"
        };
    }
    def _do_format -> dict[str, Any] {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }

        Jac.setup();
        compiler = Jac.get_compiler();

        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as f {
            f.write(code);
            tmp_path = f.name;
        }

        try {
            old_stderr = sys.stderr;
            captured = io.StringIO();
            sys.stderr = captured;

            try {
                result_prog = compiler.jac_str_formatter(code, tmp_path);
            } finally {
                sys.stderr = old_stderr;
            }

            if result_prog is None {
                stderr_output = captured.getvalue().strip();
                return {
                    "formatted": code,
                    "changed": False,
                    "error": stderr_output or "Format failed"
                };
            }

            # Get formatted source from the result
            formatted = code;
            if result_prog?.ir and result_prog.ir {
                if result_prog.ir?.source and result_prog.ir.source?.code {
                    formatted = result_prog.ir.source.code;
                }
            } elif result_prog?.source {
                formatted = str(result_prog.source);
            }

            changed = formatted != code;
            return {"formatted": formatted, "changed": changed};
        } finally {
            os.unlink(tmp_path);
        }
    }
    (success, result) = run_with_timeout(_do_format);
    if not success {
        return {"formatted": code, "changed": False, "error": str(result)};
    }
    return result;
}

"""Convert Python code to Jac."""
impl CompilerBridge.py_to_jac(python_code: str) -> dict[str, Any] {
    if len(python_code) > MAX_INPUT_SIZE {
        return {
            "jac_code": "",
            "warnings": [f"Input exceeds maximum size of {MAX_INPUT_SIZE} bytes"]
        };
    }
    def _do_py2jac -> dict[str, Any] {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        import from jaclang.jac0core.program { JacProgram }

        Jac.setup();
        compiler = Jac.get_compiler();

        with tempfile.NamedTemporaryFile(mode="w", suffix=".py", delete=False) as f {
            f.write(python_code);
            tmp_path = f.name;
        }

        try {
            program = JacProgram();

            old_stderr = sys.stderr;
            captured = io.StringIO();
            sys.stderr = captured;

            try {
                ir = compiler.compile(tmp_path, program);
            } finally {
                sys.stderr = old_stderr;
            }

            warnings: list[str] = [];
            stderr_output = captured.getvalue().strip();
            if stderr_output {
                for line in stderr_output.split("\n") {
                    if line.strip() {
                        warnings.append(line.strip());
                    }
                }
            }

            if ir is None {
                return {"jac_code": "", "warnings": warnings or ["Conversion failed"]};
            }

            # Try to get the unparsed Jac source
            jac_code = "";
            if ir?.source and ir.source?.code {
                jac_code = ir.source.code;
            } elif ir?.gen {
                jac_code = str(ir.gen.jac) if ir.gen?.jac else "";
            }

            return {"jac_code": jac_code, "warnings": warnings};
        } finally {
            os.unlink(tmp_path);
        }
    }
    (success, result) = run_with_timeout(_do_py2jac);
    if not success {
        return {"jac_code": "", "warnings": [str(result)]};
    }
    return result;
}

"""Generate IR output in the specified format."""
impl CompilerBridge.ir_gen(code: str, output_format: str) -> dict[str, Any] {
    if output_format not in IR_FORMATS {
        return {
            "output": "",
            "format": output_format,
            "valid": False,
            "errors": [
                f"Invalid format '{output_format}'. Valid: {', '.join(IR_FORMATS)}"
            ]
        };
    }
    if len(code) > MAX_INPUT_SIZE {
        return {
            "output": "",
            "format": output_format,
            "valid": False,
            "errors": [f"Input exceeds maximum size of {MAX_INPUT_SIZE} bytes"]
        };
    }
    # Map MCP-friendly names to AstTool format names
    format_map: dict[str, str] = {
        "sym_dot": "sym.",
        "ast_dot": "ast.",
        "cfg_dot": "cfg."
    };
    ir_format = format_map.get(output_format, output_format);
    def _do_ir_gen -> dict[str, Any] {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        import from jaclang.utils.lang_tools { AstTool }

        Jac.setup();

        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as f {
            f.write(code);
            tmp_path = f.name;
        }

        try {
            tool = AstTool();
            result = tool.ir([ir_format, tmp_path]);
            if result.startswith("Error") {
                return {
                    "output": "",
                    "format": output_format,
                    "valid": False,
                    "errors": [result]
                };
            }
            return {
                "output": result,
                "format": output_format,
                "valid": True,
                "errors": []
            };
        } finally {
            os.unlink(tmp_path);
        }
    }
    (success, result) = run_with_timeout(_do_ir_gen, timeout=15);
    if not success {
        return {
            "output": "",
            "format": output_format,
            "valid": False,
            "errors": [str(result)]
        };
    }
    return result;
}

"""Lint Jac code with optional auto-fix."""
impl CompilerBridge.lint_snippet(code: str, fix: bool = False) -> dict[str, Any] {
    if len(code) > MAX_INPUT_SIZE {
        return {
            "violations": [],
            "count": 0,
            "error": f"Input exceeds maximum size of {MAX_INPUT_SIZE} bytes"
        };
    }
    def _do_lint -> dict[str, Any] {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        import from jaclang.jac0core.program { JacProgram }

        Jac.setup();

        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as f {
            f.write(code);
            tmp_path = f.name;
        }

        try {
            if fix {
                prog = JacProgram.jac_str_formatter(
                    source_str=code, file_path=tmp_path, auto_lint=True
                );
            } else {
                prog = JacProgram.jac_file_linter(tmp_path);
            }

            violations: list[dict] = [];
            for error in prog.errors_had {
                loc = error.loc;
                msg = str(error?.msg or error);
                violation: dict[str, Any] = {
                    "line": loc?.first_line or 0,
                    "col": loc?.col_start or 0,
                    "message": msg
                };
                violations.append(violation);
            }

            result: dict[str, Any] = {
                "violations": violations,
                "count": len(violations)
            };

            if fix {
                fixed_code = code;
                if prog.mod and prog.mod.main and prog.mod.main.gen {
                    gen_jac = prog.mod.main.gen.jac;
                    if gen_jac {
                        fixed_code = str(gen_jac);
                    }
                }
                result["fixed_code"] = fixed_code;
            }

            return result;
        } finally {
            os.unlink(tmp_path);
        }
    }
    (success, result) = run_with_timeout(_do_lint);
    if not success {
        return {"violations": [], "count": 0, "error": str(result)};
    }
    return result;
}

"""Compile Jac code to Python."""
impl CompilerBridge.jac_to_py_code(code: str) -> dict[str, Any] {
    if len(code) > MAX_INPUT_SIZE {
        return {
            "python_code": "",
            "errors": [f"Input exceeds maximum size of {MAX_INPUT_SIZE} bytes"]
        };
    }
    def _do_jac2py -> dict[str, Any] {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        import from jaclang.jac0core.program { JacProgram }

        Jac.setup();

        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as f {
            f.write(code);
            tmp_path = f.name;
        }

        try {
            prog = JacProgram();

            old_stderr = sys.stderr;
            captured = io.StringIO();
            sys.stderr = captured;

            try {
                ir = prog.compile(tmp_path);
            } finally {
                sys.stderr = old_stderr;
            }

            errors: list[str] = [];
            stderr_output = captured.getvalue().strip();
            if stderr_output {
                for line in stderr_output.split("\n") {
                    if line.strip() {
                        errors.append(line.strip());
                    }
                }
            }

            if ir is None {
                return {"python_code": "", "errors": errors or ["Compilation failed"]};
            }

            py_code = "";
            if ir.gen and ir.gen.py {
                py_out = ir.gen.py;
                if isinstance(py_out, list) {
                    py_code = str(py_out[0]) if py_out else "";
                } else {
                    py_code = str(py_out);
                }
            }

            return {"python_code": py_code, "errors": errors};
        } finally {
            os.unlink(tmp_path);
        }
    }
    (success, result) = run_with_timeout(_do_jac2py);
    if not success {
        return {"python_code": "", "errors": [str(result)]};
    }
    return result;
}

"""Compile Jac code to JavaScript."""
impl CompilerBridge.jac_to_js_code(code: str) -> dict[str, Any] {
    if len(code) > MAX_INPUT_SIZE {
        return {
            "js_code": "",
            "errors": [f"Input exceeds maximum size of {MAX_INPUT_SIZE} bytes"]
        };
    }
    def _do_jac2js -> dict[str, Any] {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        import from jaclang.jac0core.program { JacProgram }
        import from jaclang.compiler.passes.ecmascript { EsastGenPass }
        import from jaclang.compiler.passes.ecmascript.es_unparse { es_to_js }
        import from jaclang.compiler.passes.ecmascript.estree { Node as EsNode }

        Jac.setup();

        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as f {
            f.write(code);
            tmp_path = f.name;
        }

        try {
            prog = JacProgram();

            old_stderr = sys.stderr;
            captured = io.StringIO();
            sys.stderr = captured;

            try {
                ir = prog.compile(tmp_path, no_cgen=True);
            } finally {
                sys.stderr = old_stderr;
            }

            errors: list[str] = [];
            stderr_output = captured.getvalue().strip();
            if stderr_output {
                for line in stderr_output.split("\n") {
                    if line.strip() {
                        errors.append(line.strip());
                    }
                }
            }

            if ir is None {
                return {"js_code": "", "errors": errors or ["Compilation failed"]};
            }

            try {
                esast_pass = EsastGenPass(ir, prog);
                es_ir = esast_pass.ir_out;
                es_ast = es_ir.gen.es_ast;
                if isinstance(es_ast, EsNode) {
                    js_code = es_to_js(es_ast);
                    return {"js_code": js_code, "errors": errors};
                } else {
                    errors.append("ECMAScript AST generation failed");
                    return {"js_code": "", "errors": errors};
                }
            } except Exception as e {
                errors.append(f"JavaScript generation failed: {e}");
                return {"js_code": "", "errors": errors};
            }
        } finally {
            os.unlink(tmp_path);
        }
    }
    (success, result) = run_with_timeout(_do_jac2js, timeout=15);
    if not success {
        return {"js_code": "", "errors": [str(result)]};
    }
    return result;
}
