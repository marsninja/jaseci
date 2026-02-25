"""Implementation of the nacompile command.

Compiles a .na.jac file to a standalone ELF binary:
1. Compile .na.jac through Jac pipeline to get LLVM IR
2. Inject _start entry point into the IR
3. Emit object code via llvmlite
4. Link into ELF executable via pure Python ELF linker
"""

import os;

import from jaclang.cli.console { console }

"""Inject a _start function into LLVM IR that calls jac_entry and exit."""
def _inject_start(llvm_ir_str: str) -> str {
    # Add a main() function so we can use __libc_start_main for proper CRT init.
    # The ELF linker will inject a _start stub (raw x86_64 bytes) that reads
    # argc/argv from the stack and calls __libc_start_main(@main, argc, argv, ...).
    # This ensures pthread, GC, and other libc subsystems initialize correctly.
    start_ir = """
; --- injected main entry point ---

define i32 @main(i32 %argc, ptr %argv) {
entry:
    call void @jac_entry()
    ret i32 0
}
""";
    return llvm_ir_str + start_ir;
}


"""Compile a .na.jac file to a standalone native binary."""
impl nacompile(filename: str, output: str = "") -> int {
    # Validate input
    if not filename.endswith(".na.jac") {
        console.error("Input must be a .na.jac file.");
        return 1;
    }
    if not os.path.exists(filename) {
        console.error(f"File not found: {filename}");
        return 1;
    }

    # Determine output path
    if not output {
        output = os.path.basename(filename);
        # Strip .na.jac extension
        if output.endswith(".na.jac") {
            output = output[:-7];
        }
    }

    console.print(f"Compiling {filename} to native binary...");

    # Step 1: Compile through Jac pipeline to get LLVM IR
    import from jaclang.jac0core.program { JacProgram }
    import from jaclang.jac0core.compile_options { CompileOptions }

    try {
        prog = JacProgram();
        options = CompileOptions(skip_native_engine=True);
        ir_module = prog.compile(file_path=os.path.abspath(filename), options=options);
    } except Exception as e {
        console.error(f"Jac compilation failed: {e}");
        import traceback;
        traceback.print_exc();
        return 1;
    }

    if ir_module is None or ir_module.gen.llvm_ir is None {
        console.error("Native compilation produced no LLVM IR.");
        if prog.errors_had {
            for err in prog.errors_had {
                console.error(f"  {err}");
            }
        }
        return 1;
    }

    # Step 2: Check for Python/server interop (can't compile standalone)
    manifest = ir_module.gen.interop_manifest;
    if manifest and manifest.native_imports {
        console.error(
            "Cannot compile to standalone binary: "
            "file has Python/server dependencies (native_imports)."
        );
        for binding in manifest.native_imports {
            console.error(f"  - {binding.name}");
        }
        return 1;
    }

    llvm_ir_str = str(ir_module.gen.llvm_ir);

    # Check that jac_entry exists (requires with entry {} block)
    if "jac_entry" not in llvm_ir_str {
        console.error(
            "No entry point found. "
            "The .na.jac file must have a 'with entry { }' block."
        );
        return 1;
    }

    console.print("  LLVM IR generated successfully.");

    # Step 3: Inject _start entry point
    llvm_ir_str = _inject_start(llvm_ir_str);

    # Step 4: Emit object code via llvmlite
    import llvmlite.binding as llvm;
    llvm.initialize_all_targets();
    llvm.initialize_all_asmprinters();

    try {
        mod = llvm.parse_assembly(llvm_ir_str);
        mod.verify();
    } except Exception as e {
        console.error(f"LLVM IR verification failed: {e}");
        return 1;
    }

    target = llvm.Target.from_default_triple();
    target_machine = target.create_target_machine();
    obj_bytes = target_machine.emit_object(mod);
    console.print(f"  Object code emitted ({len(obj_bytes)} bytes).");

    # Step 5: Determine needed libraries
    import ctypes.util;
    needed_libs: list[str] = ["libc.so.6"];

    # Check if libgc is available and needed
    libgc_name = ctypes.util.find_library("gc");
    if libgc_name {
        # Check if the IR references GC functions
        if "GC_malloc" in llvm_ir_str or "GC_init" in llvm_ir_str {
            # Resolve to actual soname
            needed_libs.append("libgc.so.1");
        }
    }

    # Step 6: Link into ELF executable
    import from jaclang.compiler.passes.native.elf_linker { ElfLinker }

    try {
        success = ElfLinker.link(
            obj_bytes=obj_bytes,
            output_path=output,
            needed_libs=needed_libs
        );
    } except Exception as e {
        console.error(f"ELF linking failed: {e}");
        import traceback;
        traceback.print_exc();
        return 1;
    }

    if not success {
        console.error("ELF linking failed: could not parse object file.");
        return 1;
    }

    file_size = os.path.getsize(output);
    console.print(f"  Binary written to [bold]{output}[/bold] ({file_size} bytes).");
    console.print(f"  Run with: ./{output}");
    return 0;
}
