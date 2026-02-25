"""Pure Python ELF linker for native Jac compilation.

Takes raw object code bytes from llvmlite's emit_object() and produces
a runnable ELF executable using only Python's struct module. No external
linker (ld, cc) required.

Currently supports ELF64 x86_64 with dynamic linking against libc/libgc.
"""

import from typing { Any }

"""Parsed ELF section."""
obj ElfSection {
    has name: str,
        typ: int,
        flags: int,
        addr: int,
        data: bytes,
        mem_size: int,
        align: int,
        link: int,
        info: int,
        entsize: int;
}

"""Parsed ELF relocation."""
obj ElfRela {
    has offset: int,
        sym_idx: int,
        rtype: int,
        addend: int,
        sym_name: str,
        target_sec: str;
}

"""Parsed ELF symbol."""
obj ElfSymbol {
    has name: str,
        value: int,
        size: int,
        bind: int,
        typ: int,
        shndx: int;
}

"""Main ELF linker class.

Parses a .o file and produces a dynamically-linked ELF executable.
"""
obj ElfLinker {
    has obj_data: bytes,
        sections: list[ElfSection],
        symbols: list[ElfSymbol],
        relocations: list[ElfRela],
        needed_libs: list[str];

    """Parse a relocatable ELF object and link into an executable."""
    static def link(
        obj_bytes: bytes, output_path: str, needed_libs: list[str] = ["libc.so.6"]
    ) -> bool;

    """Parse the ELF relocatable object file."""
    def parse_object -> bool;

    """Build the final ELF executable bytes."""
    def build_executable -> bytes;
}
