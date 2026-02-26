"""Implementation of the nacompile command.

Compiles a .na.jac file to a standalone ELF binary:
1. Compile .na.jac through Jac pipeline to get LLVM IR
2. Inject _start entry point into the IR
3. Emit object code via llvmlite
4. Link into ELF executable via pure Python ELF linker
"""

import os;

import from jaclang.cli.console { console }

"""Inline asm for x86_64 _start: extracts argc/argv from stack, calls __libc_start_main."""
glob _X86_64_START_ASM = (
         "xorl %ebp, %ebp\\0A"
         "popq %rsi\\0A"
         "movq %rsp, %rdx\\0A"
         "andq $$-16, %rsp\\0A"
         "pushq %rax\\0A"
         "pushq %rsp\\0A"
         "xorl %r9d, %r9d\\0A"
         "xorl %r8d, %r8d\\0A"
         "xorl %ecx, %ecx\\0A"
         "leaq main(%rip), %rdi\\0A"
         "callq __libc_start_main\\0A"
         "hlt"
     );

"""Inline asm for aarch64 _start: extracts argc/argv, calls __libc_start_main."""
glob _AARCH64_START_ASM = (
         "mov x29, #0\\0A"
         "mov x30, #0\\0A"
         "mov x1, x0\\0A"
         "adrp x0, main\\0A"
         "add x0, x0, :lo12:main\\0A"
         "ldr x2, [sp]\\0A"
         "add x3, sp, #8\\0A"
         "mov x4, #0\\0A"
         "mov x5, #0\\0A"
         "mov x6, sp\\0A"
         "bl __libc_start_main\\0A"
         "brk #1"
     );

"""Clobber constraints for x86_64 inline asm."""
glob _X86_64_CLOBBERS = "~{dirflag},~{fpsr},~{flags},~{memory}";

"""Clobber constraints for aarch64 inline asm."""
glob _AARCH64_CLOBBERS = "~{memory}";


"""Inject _start and main functions into LLVM IR for standalone binary.

Generates _start via architecture-specific inline assembly so LLVM produces
proper relocations. The ELF linker treats _start like any other function.
"""
def _inject_start(llvm_ir_str: str, triple: str) -> str {
    arch = triple.split("-")[0];
    if arch == "x86_64" {
        asm_body = _X86_64_START_ASM;
        clobbers = _X86_64_CLOBBERS;
    } elif arch == "aarch64" {
        asm_body = _AARCH64_START_ASM;
        clobbers = _AARCH64_CLOBBERS;
    } else {
        asm_body = "";
        clobbers = "";
    }
    start_ir = '\n; --- injected entry points ---\n' + 'declare i32 @__libc_start_main(ptr, i32, ptr, ptr, ptr, ptr, ptr)\n\n' + 'define i32 @main(i32 %argc, ptr %argv) {\n' + 'entry:\n' + '    call void @jac_entry()\n' + '    ret i32 0\n' + '}\n\n';
    if asm_body {
        start_ir += (
            'define void @_start() naked noreturn nounwind {\n' + 'entry:\n' + '    call void asm sideeffect "' + asm_body + '", "' + clobbers + '"()\n' + '    unreachable\n' + '}\n'
        );
    }
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

    # Step 3: Initialize llvmlite and detect target architecture
    import llvmlite.binding as llvm;
    llvm.initialize_all_targets();
    llvm.initialize_all_asmprinters();
    llvm.initialize_native_asmparser();

    triple = llvm.get_default_triple();
    arch = triple.split("-")[0];
    console.print(f"  Target: {triple}");

    # Step 4: Inject _start entry point (architecture-specific via inline asm)
    llvm_ir_str = _inject_start(llvm_ir_str, triple);

    # Step 5: Determine needed libraries and handle GC fallback
    # (must happen before parse_assembly so IR substitutions take effect)
    import ctypes.util;
    needed_libs: list[str] = ["libc.so.6"];

    libgc_name = ctypes.util.find_library("gc");
    gc_needed = "GC_malloc" in llvm_ir_str or "GC_add_roots" in llvm_ir_str;
    if gc_needed and libgc_name {
        needed_libs.append("libgc.so.1");
    } elif gc_needed {
        # libgc not available: rewrite GC calls to libc fallbacks at IR level.
        # GC_malloc -> malloc, GC_add_roots -> noop stub (matching JIT fallback).
        import re;
        llvm_ir_str = llvm_ir_str.replace(
            'declare i8* @"GC_malloc"(i64 %".1")', 'declare i8* @"malloc"(i64 %".1")'
        );
        llvm_ir_str = re.sub(
            r'call i8\* @"GC_malloc"\(', 'call i8* @"malloc"(', llvm_ir_str
        );
        # Replace GC_add_roots with a no-op: remove calls and declaration
        llvm_ir_str = re.sub(r'call void @"GC_add_roots"\([^)]*\)\n', '', llvm_ir_str);
        llvm_ir_str = llvm_ir_str.replace(
            'declare void @"GC_add_roots"(i8* %".1", i8* %".2")', ''
        );
        console.print("  Note: libgc not found, using malloc fallback.");
    }

    # Step 6: Emit object code via llvmlite
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

    # Step 7: Link into ELF executable
    import from jaclang.compiler.passes.native.elf_linker { ElfLinker }

    try {
        success = ElfLinker.link(
            obj_bytes=obj_bytes, output_path=output, needed_libs=needed_libs
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
