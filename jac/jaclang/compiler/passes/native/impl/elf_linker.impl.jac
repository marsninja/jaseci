"""Pure Python ELF64 linker implementation.

Converts a relocatable .o (from llvmlite emit_object) into a runnable
ELF executable with dynamic linking against libc/libgc.
"""

import struct;
import os;

# ── ELF header ───────────────────────────────────────────────────
glob ELFMAG = b"\x7fELF",
     ELFCLASS64 = 2,
     ELFDATA2LSB = 1,
     ET_EXEC = 2,
     EM_X86_64 = 62;

# ── Section header types ─────────────────────────────────────────
glob SHT_NULL = 0,
     SHT_PROGBITS = 1,
     SHT_SYMTAB = 2,
     SHT_STRTAB = 3,
     SHT_RELA = 4,
     SHT_HASH = 5,
     SHT_DYNAMIC = 6,
     SHT_DYNSYM = 11;

# ── Section flags ────────────────────────────────────────────────
glob SHF_WRITE = 0x1,
     SHF_ALLOC = 0x2,
     SHF_EXECINSTR = 0x4;

# ── Program header types ─────────────────────────────────────────
glob PT_NULL = 0,
     PT_LOAD = 1,
     PT_DYNAMIC = 2,
     PT_INTERP = 3,
     PT_PHDR = 6;

# ── Program header flags ─────────────────────────────────────────
glob PF_X = 0x1,
     PF_W = 0x2,
     PF_R = 0x4;

# ── Dynamic section tags ─────────────────────────────────────────
glob DT_NULL = 0,
     DT_NEEDED = 1,
     DT_HASH = 4,
     DT_STRTAB = 5,
     DT_SYMTAB = 6,
     DT_STRSZ = 10,
     DT_SYMENT = 11,
     DT_DEBUG = 21,
     DT_PLTGOT = 3,
     DT_PLTRELSZ = 2,
     DT_PLTREL = 20,
     DT_JMPREL = 23,
     DT_RELA = 7;

# ── Relocation types (x86_64) ────────────────────────────────────
glob R_X86_64_64 = 1,
     R_X86_64_PC32 = 2,
     R_X86_64_PLT32 = 4,
     R_X86_64_GOTPCREL = 9,
     R_X86_64_JUMP_SLOT = 7;

# ── Symbol binding/type ──────────────────────────────────────────
glob STB_GLOBAL = 1,
     STT_FUNC = 2,
     STT_NOTYPE = 0,
     SHN_UNDEF = 0;

# ── Layout constants ─────────────────────────────────────────────
glob PAGE_SIZE = 0x1000,
     BASE_VADDR = 0x400000,
     INTERP_PATH = b"/lib64/ld-linux-x86-64.so.2";


# ── Helper: align to boundary ────────────────────────────────────
def _align(value: int, alignment: int) -> int {
    if alignment <= 1 {
        return value;
    }
    return (value + alignment - 1) & ~(alignment - 1);
}


# ── Helper: build ELF string table ──────────────────────────────
def _build_strtab(strings: list[str]) -> tuple[bytes, dict[str, int]] {
    """Build a string table and return (bytes, {name: offset})."""
    data = bytearray(b"\x00");  # First byte is null
    offsets: dict[str, int] = {};
    for s in strings {
        if s not in offsets {
            offsets[s] = len(data);
            data.extend(s.encode("utf-8") + b"\x00");
        }
    }
    return (bytes(data), offsets);
}


# ── Helper: build ELF hash table ────────────────────────────────
def _elf_hash(name: str) -> int {
    """Compute ELF hash for a symbol name."""
    h = 0;
    for c in name.encode("utf-8") {
        h = (h << 4) + c;
        g = h & 0xF0000000;
        if g {
            h ^= g >> 24;
        }
        h &= ~g;
    }
    return h;
}


def _build_hash_table(num_symbols: int) -> bytes {
    """Build a minimal ELF hash table.

    Uses nbucket=1 so all symbols hash to bucket 0, chained together.
    Simple but correct for small symbol counts.
    """
    nbucket = 1;
    nchain = num_symbols;
    # All symbols go to bucket 0
    data = bytearray();
    data.extend(struct.pack("<II", nbucket, nchain));
    # Bucket[0] = 1 (first non-null symbol)
    data.extend(struct.pack("<I", 1 if num_symbols > 1 else 0));
    # Chain: chain[0] = 0 (STN_UNDEF), chain[i] = i+1, chain[last] = 0
    for i in range(nchain) {
        if i == 0 {
            data.extend(struct.pack("<I", 0));  # STN_UNDEF chains to nothing
        } elif i == nchain - 1 {
            data.extend(struct.pack("<I", 0));  # Last symbol chains to nothing
        } else {
            data.extend(struct.pack("<I", i + 1));  # Chain to next
        }
    }
    return bytes(data);
}


# ── Parse the relocatable object ─────────────────────────────────
impl ElfLinker.parse_object -> bool {
    raw = self.obj_data;
    if len(raw) < 64 or raw[:4] != ELFMAG {
        return False;
    }
    # Parse ELF header
    (
        e_type,
        e_machine,
        e_version,
        e_entry,
        e_phoff,
        e_shoff,
        e_flags,
        e_ehsize,
        e_phentsize,
        e_phnum,
        e_shentsize,
        e_shnum,
        e_shstrndx
    ) = struct.unpack_from("<HHIQQQIHHHHHH", raw, 16);
    if e_type != 1 {  # Must be ET_REL
        return False;
    }

    # Parse section headers
    raw_sections: list[dict] = [];
    for i in range(e_shnum) {
        off = e_shoff + i * e_shentsize;
        (
            sh_name,
            sh_type,
            sh_flags,
            sh_addr,
            sh_offset,
            sh_size,
            sh_link,
            sh_info,
            sh_addralign,
            sh_entsize
        ) = struct.unpack_from("<IIQQQQIIQQ", raw, off);
        raw_sections.append(
            {
                "name_idx": sh_name,
                "type": sh_type,
                "flags": sh_flags,
                "addr": sh_addr,
                "offset": sh_offset,
                "size": sh_size,
                "link": sh_link,
                "info": sh_info,
                "align": sh_addralign,
                "entsize": sh_entsize
            }
        );
    }

    # Get section name string table
    shstrtab = raw_sections[e_shstrndx];
    shstrtab_data = raw[shstrtab["offset"]:shstrtab["offset"] + shstrtab["size"]];

    # Build section list
    self.sections = [];
    for rs in raw_sections {
        name_end = shstrtab_data.index(b"\x00", rs["name_idx"]);
        name = shstrtab_data[rs["name_idx"]:name_end].decode();
        # For NOBITS (BSS), there's no file data but mem_size = sh_size
        sh_type = rs["type"];
        sh_size = rs["size"];
        if sh_type == 8 {  # SHT_NOBITS
            data = b"";
            mem_sz = sh_size;
        } else {
            data = raw[rs["offset"]:rs["offset"] + sh_size] if sh_size > 0 else b"";
            mem_sz = sh_size;
        }
        self.sections.append(
            ElfSection(
                name=name,
                typ=sh_type,
                flags=rs["flags"],
                addr=rs["addr"],
                data=data,
                mem_size=mem_sz,
                align=rs["align"],
                link=rs["link"],
                info=rs["info"],
                entsize=rs["entsize"]
            )
        );
    }

    # Parse symbol table
    self.symbols = [];
    symtab_sec = None;
    strtab_data = b"\x00";
    for sec in self.sections {
        if sec.typ == SHT_SYMTAB {
            symtab_sec = sec;
            strtab_data = self.sections[sec.link].data;
            break;
        }
    }
    if symtab_sec is not None {
        num_syms = len(symtab_sec.data) // symtab_sec.entsize
        if symtab_sec.entsize
        else 0;
        for i in range(num_syms) {
            off = i * symtab_sec.entsize;
            (
                st_name,
                st_info,
                st_other,
                st_shndx,
                st_value,
                st_size
            ) = struct.unpack_from("<IBBHQQ", symtab_sec.data, off);
            end = strtab_data.index(b"\x00", st_name);
            name = strtab_data[st_name:end].decode();
            self.symbols.append(
                ElfSymbol(
                    name=name,
                    value=st_value,
                    size=st_size,
                    bind=st_info >> 4,
                    typ=st_info & 0xF,
                    shndx=st_shndx
                )
            );
        }
    }

    # Parse relocations — include all .rela.* sections except eh_frame
    self.relocations = [];
    for sec in self.sections {
        if sec.typ == SHT_RELA and "eh_frame" not in sec.name {
            # Determine target section name from .rela.XXX -> XXX
            target_name = sec.name;
            if target_name.startswith(".rela.") {
                target_name = "." + target_name[6:];
            } elif target_name.startswith(".rela") {
                target_name = "." + target_name[5:];
            }
            num_relas = len(sec.data) // 24 if len(sec.data) >= 24 else 0;
            for i in range(num_relas) {
                (
                    r_offset,
                    r_info,
                    r_addend
                ) = struct.unpack_from("<QQq", sec.data, i * 24);
                r_sym = r_info >> 32;
                r_type = r_info & 0xFFFFFFFF;
                sym_name = self.symbols[r_sym].name if r_sym < len(self.symbols) else "";
                self.relocations.append(
                    ElfRela(
                        offset=r_offset,
                        sym_idx=r_sym,
                        rtype=r_type,
                        addend=r_addend,
                        sym_name=sym_name,
                        target_sec=target_name
                    )
                );
            }
        }
    }
    return True;
}


# ── Build the executable ─────────────────────────────────────────
impl ElfLinker.build_executable -> bytes {
    # Collect code and data sections from the .o file
    code_data = bytearray();
    rodata_blob = bytearray();
    data_blob = bytearray();
    bss_size = 0;

    # Maps: section name -> offset within its blob
    code_sections: dict[str, tuple[int, int]] = {};   # name -> (offset_in_code, size)
    rodata_sections: dict[str, tuple[int, int]] = {};
    data_sections: dict[str, tuple[int, int]] = {};

    # Map from .o section index to (segment_type, offset_in_segment)
    section_placement: dict[int, tuple[str, int]] = {};
    sec_idx = 0;
    for sec in self.sections {
        if sec.typ == SHT_PROGBITS and (sec.flags & SHF_EXECINSTR) {
            # Code section (.text, .ltext)
            if len(sec.data) > 0 {
                aligned_off = _align(len(code_data), max(sec.align, 1));
                code_data.extend(b"\x00" * (aligned_off - len(code_data)));
                code_sections[sec.name] = (len(code_data), len(sec.data));
                section_placement[sec_idx] = ("code", len(code_data));
                code_data.extend(sec.data);
            }
        } elif sec.typ == SHT_PROGBITS
        and (sec.flags & SHF_ALLOC)
        and not (sec.flags & SHF_WRITE) {
            # Read-only data (.rodata, .lrodata)
            if len(sec.data) > 0 {
                aligned_off = _align(len(rodata_blob), max(sec.align, 1));
                rodata_blob.extend(b"\x00" * (aligned_off - len(rodata_blob)));
                rodata_sections[sec.name] = (len(rodata_blob), len(sec.data));
                section_placement[sec_idx] = ("rodata", len(rodata_blob));
                rodata_blob.extend(sec.data);
            }
        } elif (sec.flags & SHF_WRITE) and (sec.flags & SHF_ALLOC) {
            # Writable data (.data, .ldata) or BSS (.bss, .lbss)
            alloc_size = sec.mem_size;
            if alloc_size > 0 {
                aligned_off = _align(len(data_blob), max(sec.align, 1));
                data_blob.extend(b"\x00" * (aligned_off - len(data_blob)));
                data_sections[sec.name] = (len(data_blob), alloc_size);
                section_placement[sec_idx] = ("data", len(data_blob));
                if len(sec.data) > 0 {
                    data_blob.extend(sec.data);
                    if alloc_size > len(sec.data) {
                        data_blob.extend(b"\x00" * (alloc_size - len(sec.data)));
                    }
                } else {
                    data_blob.extend(b"\x00" * alloc_size);
                }
            }
        }
        sec_idx += 1;
    }

    # Identify external symbols (undefined, need dynamic linking)
    extern_syms: list[str] = [];
    local_sym_map: dict[str, tuple[str, int]] = {};  # name -> (segment, offset_in_segment)
    # Also build a map from symbol index to placement for section symbols (empty name)
    sym_idx_placement: dict[int, tuple[str, int]] = {};  # sym_idx -> (segment, base_offset)
    sym_i = 0;
    for sym in self.symbols {
        if sym.shndx == SHN_UNDEF and sym.name and sym.bind == STB_GLOBAL {
            if sym.name not in extern_syms {
                extern_syms.append(sym.name);
            }
        } elif sym.shndx != SHN_UNDEF and sym.shndx < len(self.sections) {
            placement = section_placement.get(sym.shndx);
            if placement is not None {
                if sym.name {
                    local_sym_map[sym.name] = (placement[0], placement[1] + sym.value);
                }
                # For section symbols (empty name or STT_SECTION), store base placement by index
                sym_idx_placement[sym_i] = (placement[0], placement[1]);
            }
        }
        sym_i += 1;
    }

    # ── Inject _start stub for CRT initialization ────────────────
    # If 'main' is defined and __libc_start_main is not already an extern,
    # add it so we can build a proper _start that uses libc's CRT init.
    # This ensures GC_malloc, pthread, and other libc features work.
    has_main = "main" in local_sym_map;
    needs_libc_start = has_main and "__libc_start_main" not in extern_syms;
    if needs_libc_start {
        extern_syms.append("__libc_start_main");
    }
    # Reserve space for _start stub in code_data (addresses patched later)
    start_stub_offset = -1;
    if has_main {
        aligned_off = _align(len(code_data), 16);
        code_data.extend(b"\x00" * (aligned_off - len(code_data)));
        start_stub_offset = len(code_data);
        # 48 bytes for the stub (will be patched after layout is known)
        code_data.extend(b"\x00" * 48);
    }

    # ── Layout ────────────────────────────────────────────────────
    # ELF header: 64 bytes
    # Program headers: 5 * 56 = 280 bytes
    # Then: .interp, .hash, .dynsym, .dynstr, .rela.plt, .plt, .text+rodata, .data+.got.plt+.dynamic
    ehdr_size = 64;
    num_phdrs = 5;  # PHDR, INTERP, LOAD (code), LOAD (data), DYNAMIC
    phdr_size = num_phdrs * 56;

    # Build interp
    interp_data = INTERP_PATH + b"\x00";
    # Check for fallback interp path
    if not os.path.exists(INTERP_PATH.decode()) {
        alt_interp = b"/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2";
        if os.path.exists(alt_interp.decode()) {
            interp_data = alt_interp + b"\x00";
        }
    }

    # Build dynamic string table
    dynstr_strings = [""] + extern_syms + self.needed_libs;
    (dynstr_data, dynstr_offsets) = _build_strtab(dynstr_strings);

    # Build dynamic symbol table (STN_UNDEF + one entry per extern)
    # Each entry: 24 bytes (Elf64_Sym)
    num_dynsyms = 1 + len(extern_syms);  # STN_UNDEF + externals
    dynsym_data = bytearray();
    dynsym_data.extend(struct.pack("<IBBHQQ", 0, 0, 0, 0, 0, 0));  # STN_UNDEF
    for sym_name in extern_syms {
        st_name = dynstr_offsets.get(sym_name, 0);
        st_info = (STB_GLOBAL << 4) | STT_FUNC;
        dynsym_data.extend(
            struct.pack("<IBBHQQ", st_name, st_info, 0, SHN_UNDEF, 0, 0)
        );
    }

    # Build hash table
    hash_data = _build_hash_table(num_dynsyms);

    # Build .rela.plt (one R_X86_64_JUMP_SLOT per extern)
    # Actual offsets will be patched after layout
    rela_plt_data = bytearray();

    # Build PLT
    # PLT[0]: push [GOT+8]; jmp [GOT+16]
    # PLT[n]: jmp [GOT+24+8*n]; push n; jmp PLT[0]
    plt_entry_size = 16;
    plt0_size = 16;
    plt_size = plt0_size + len(extern_syms) * plt_entry_size;
    # PLT will be built after addresses are known

    # GOT.PLT: 3 reserved entries + one per extern
    got_plt_entries = 3 + len(extern_syms);
    got_plt_size = got_plt_entries * 8;

    # Dynamic section entries
    dyn_entries: list[tuple[int, int]] = [];
    for lib in self.needed_libs {
        dyn_entries.append((DT_NEEDED, dynstr_offsets.get(lib, 0)));
    }
    # Placeholders for addresses (filled after layout)
    dyn_entries.append((DT_HASH, 0));
    dyn_entries.append((DT_STRTAB, 0));
    dyn_entries.append((DT_SYMTAB, 0));
    dyn_entries.append((DT_STRSZ, len(dynstr_data)));
    dyn_entries.append((DT_SYMENT, 24));
    dyn_entries.append((DT_PLTGOT, 0));
    dyn_entries.append((DT_PLTRELSZ, len(extern_syms) * 24));
    dyn_entries.append((DT_PLTREL, DT_RELA));
    dyn_entries.append((DT_JMPREL, 0));
    dyn_entries.append((DT_DEBUG, 0));
    dyn_entries.append((DT_NULL, 0));
    dynamic_data = bytearray();
    for (tag, val) in dyn_entries {
        dynamic_data.extend(struct.pack("<qQ", tag, val));
    }

    # ── Compute file offsets and virtual addresses ────────────────
    # Code segment (PT_LOAD RX): ehdr + phdrs + interp + hash + dynsym + dynstr + rela.plt + plt + code + rodata
    # Data segment (PT_LOAD RW): .got.plt + .dynamic + .data
    code_seg_start = 0;  # File offset 0 for code segment

    # All the metadata sections go before .text in the code segment
    cur_offset = ehdr_size + phdr_size;
    interp_foff = cur_offset;
    cur_offset += len(interp_data);
    cur_offset = _align(cur_offset, 8);
    hash_foff = cur_offset;
    cur_offset += len(hash_data);
    cur_offset = _align(cur_offset, 8);
    dynsym_foff = cur_offset;
    cur_offset += len(dynsym_data);
    cur_offset = _align(cur_offset, 8);
    dynstr_foff = cur_offset;
    cur_offset += len(dynstr_data);
    cur_offset = _align(cur_offset, 8);
    rela_plt_foff = cur_offset;
    cur_offset += len(extern_syms) * 24;
    cur_offset = _align(cur_offset, 16);
    plt_foff = cur_offset;
    cur_offset += plt_size;
    cur_offset = _align(cur_offset, 16);
    text_foff = cur_offset;
    cur_offset += len(code_data);
    cur_offset = _align(cur_offset, 16);
    rodata_foff = cur_offset;
    cur_offset += len(rodata_blob);
    code_seg_size = cur_offset;

    # Data segment on a new page — GOT.PLT must be writable (dynamic linker patches it)
    data_seg_foff = _align(cur_offset, PAGE_SIZE);
    data_seg_vaddr = BASE_VADDR + data_seg_foff;
    got_plt_foff = data_seg_foff;
    cur_offset = data_seg_foff + got_plt_size;
    cur_offset = _align(cur_offset, 8);
    dynamic_foff = cur_offset;
    cur_offset += len(dynamic_data);
    cur_offset = _align(cur_offset, 8);
    data_foff = cur_offset;
    cur_offset += len(data_blob);
    data_seg_size = cur_offset - data_seg_foff;
    total_file_size = data_seg_foff + data_seg_size;

    # Virtual addresses
    interp_vaddr = BASE_VADDR + interp_foff;
    hash_vaddr = BASE_VADDR + hash_foff;
    dynsym_vaddr = BASE_VADDR + dynsym_foff;
    dynstr_vaddr = BASE_VADDR + dynstr_foff;
    rela_plt_vaddr = BASE_VADDR + rela_plt_foff;
    plt_vaddr = BASE_VADDR + plt_foff;
    got_plt_vaddr = BASE_VADDR + got_plt_foff;
    text_vaddr = BASE_VADDR + text_foff;
    rodata_vaddr = BASE_VADDR + rodata_foff;
    dynamic_vaddr = BASE_VADDR + dynamic_foff;
    data_vaddr = BASE_VADDR + data_foff;

    # ── Patch dynamic section addresses ───────────────────────────
    dyn_entries_patched: list[tuple[int, int]] = [];
    for (tag, val) in dyn_entries {
        if tag == DT_HASH {
            dyn_entries_patched.append((tag, hash_vaddr));
        } elif tag == DT_STRTAB {
            dyn_entries_patched.append((tag, dynstr_vaddr));
        } elif tag == DT_SYMTAB {
            dyn_entries_patched.append((tag, dynsym_vaddr));
        } elif tag == DT_PLTGOT {
            dyn_entries_patched.append((tag, got_plt_vaddr));
        } elif tag == DT_JMPREL {
            dyn_entries_patched.append((tag, rela_plt_vaddr));
        } else {
            dyn_entries_patched.append((tag, val));
        }
    }
    dynamic_data = bytearray();
    for (tag, val) in dyn_entries_patched {
        dynamic_data.extend(struct.pack("<qQ", tag, val));
    }

    # ── Build PLT ─────────────────────────────────────────────────
    # x86_64 PLT layout:
    # PLT[0]: push [GOT+8]; jmp [GOT+16]; nop padding
    # PLT[n]: jmp [GOT+24+8*(n-1)]; push (n-1); jmp PLT[0]
    plt_data = bytearray();
    # PLT[0] stub
    # ff 35 XX XX XX XX    push QWORD [rip + got_plt+8 - (plt+6)]
    # ff 25 XX XX XX XX    jmp  QWORD [rip + got_plt+16 - (plt+12)]
    # 0f 1f 40 00          nop dword [rax+0]
    got8_rel = (got_plt_vaddr + 8) - (plt_vaddr + 6);
    got16_rel = (got_plt_vaddr + 16) - (plt_vaddr + 12);
    plt_data.extend(b"\xff\x35" + struct.pack("<i", got8_rel));
    plt_data.extend(b"\xff\x25" + struct.pack("<i", got16_rel));
    plt_data.extend(b"\x0f\x1f\x40\x00");  # nop padding
    # PLT[n] stubs
    for idx in range(len(extern_syms)) {
        entry_vaddr = plt_vaddr + plt0_size + idx * plt_entry_size;
        got_entry_vaddr = got_plt_vaddr + (3 + idx) * 8;
        # ff 25 XX XX XX XX    jmp QWORD [rip + got_entry - (entry+6)]
        jmp_rel = got_entry_vaddr - (entry_vaddr + 6);
        plt_data.extend(b"\xff\x25" + struct.pack("<i", jmp_rel));
        # 68 XX XX XX XX       push idx
        plt_data.extend(b"\x68" + struct.pack("<i", idx));
        # e9 XX XX XX XX       jmp PLT[0]  (6+5+5=16 bytes total)
        jmp_plt0_rel = plt_vaddr - (entry_vaddr + 16);
        plt_data.extend(b"\xe9" + struct.pack("<i", jmp_plt0_rel));
    }

    # ── Build GOT.PLT ────────────────────────────────────────────
    got_plt_data = bytearray();
    got_plt_data.extend(struct.pack("<Q", dynamic_vaddr));  # GOT[0] = .dynamic
    got_plt_data.extend(struct.pack("<Q", 0));  # GOT[1] = link_map (filled by ld.so)
    got_plt_data.extend(struct.pack("<Q", 0));  # GOT[2] = _dl_runtime_resolve (filled by ld.so)
    for idx in range(len(extern_syms)) {
        # Initially points to the push instruction in PLT[n] (lazy binding)
        push_addr = plt_vaddr + plt0_size + idx * plt_entry_size + 6;
        got_plt_data.extend(struct.pack("<Q", push_addr));
    }

    # ── Build .rela.plt ──────────────────────────────────────────
    rela_plt_data = bytearray();
    for idx in range(len(extern_syms)) {
        r_offset = got_plt_vaddr + (3 + idx) * 8;
        r_info = ((idx + 1) << 32) | R_X86_64_JUMP_SLOT;
        r_addend = 0;
        rela_plt_data.extend(struct.pack("<QQq", r_offset, r_info, r_addend));
    }

    # ── Apply relocations to code ────────────────────────────────
    # Build PLT address map for external symbols
    extern_plt_addr: dict[str, int] = {};
    plt_idx = 0;
    for sym_name in extern_syms {
        extern_plt_addr[sym_name] = plt_vaddr + plt0_size + plt_idx * plt_entry_size;
        plt_idx += 1;
    }

    code_bytes = bytearray(code_data);
    rodata_bytes = bytearray(rodata_blob);
    data_bytes = bytearray(data_blob);

    for rela in self.relocations {
        # Resolve the symbol address
        sym_addr = 0;
        is_external = rela.sym_name in extern_plt_addr;
        if is_external {
            sym_addr = extern_plt_addr[rela.sym_name];
        } else {
            # Try named symbol first, then section symbol by index
            local = local_sym_map.get(rela.sym_name) if rela.sym_name else None;
            if local is None {
                # Section symbol (empty name) — use sym_idx_placement + addend
                sec_place = sym_idx_placement.get(rela.sym_idx);
                if sec_place is not None {
                    local = sec_place;
                }
            }
            if local is not None {
                (seg, seg_off) = local;
                if seg == "code" {
                    sym_addr = text_vaddr + seg_off;
                } elif seg == "rodata" {
                    sym_addr = rodata_vaddr + seg_off;
                } elif seg == "data" {
                    sym_addr = data_vaddr + seg_off;
                }
            }
        }

        # Determine which buffer, base vaddr, and section offset to patch
        # rela.offset is relative to the target section; add the section's
        # offset within the merged blob
        target_is_code = rela.target_sec in code_sections;
        target_is_data = rela.target_sec in data_sections;
        target_is_rodata = rela.target_sec in rodata_sections;
        if target_is_code {
            sec_blob_off = code_sections[rela.target_sec][0];
            patch_buf = code_bytes;
            patch_base_vaddr = text_vaddr + sec_blob_off;
        } elif target_is_data {
            sec_blob_off = data_sections[rela.target_sec][0];
            patch_buf = data_bytes;
            patch_base_vaddr = data_vaddr + sec_blob_off;
        } elif target_is_rodata {
            sec_blob_off = rodata_sections[rela.target_sec][0];
            patch_buf = rodata_bytes;
            patch_base_vaddr = rodata_vaddr + sec_blob_off;
        } else {
            # Default: assume code section
            sec_blob_off = 0;
            patch_buf = code_bytes;
            patch_base_vaddr = text_vaddr;
        }
        patch_off = sec_blob_off + rela.offset;

        # Apply relocation
        if rela.rtype == R_X86_64_64 {
            val = sym_addr + rela.addend;
            struct.pack_into("<Q", patch_buf, patch_off, val & 0xFFFFFFFFFFFFFFFF);
        } elif rela.rtype == R_X86_64_PC32 or rela.rtype == R_X86_64_PLT32 {
            p = patch_base_vaddr + patch_off;
            val = sym_addr + rela.addend - p;
            struct.pack_into("<i", patch_buf, patch_off, val);
        } elif rela.rtype == R_X86_64_GOTPCREL {
            if is_external {
                got_idx = extern_syms.index(rela.sym_name);
                got_entry_addr = got_plt_vaddr + (3 + got_idx) * 8;
            } else {
                got_entry_addr = 0;
            }
            p = patch_base_vaddr + patch_off;
            val = got_entry_addr + rela.addend - p;
            struct.pack_into("<i", patch_buf, patch_off, val);
        }
    }

    # ── Find entry point and build _start stub ───────────────────
    if has_main and start_stub_offset >= 0 {
        # Resolve main's virtual address
        main_local = local_sym_map.get("main");
        main_vaddr = text_vaddr + (main_local[1] if main_local is not None else 0);
        # Resolve __libc_start_main PLT address
        libc_start_plt = extern_plt_addr.get("__libc_start_main", 0);
        # Build the x86_64 _start stub
        stub = bytearray();
        stub.extend(b"\x31\xed");                                      # xor ebp, ebp
        stub.extend(b"\x5e");                                          # pop rsi (argc)
        stub.extend(b"\x48\x89\xe2");                                  # mov rdx, rsp (argv)
        stub.extend(b"\x48\x83\xe4\xf0");                              # and rsp, -16
        stub.extend(b"\x50");                                          # push rax
        stub.extend(b"\x54");                                          # push rsp (stack_end)
        stub.extend(b"\x45\x31\xc9");                                  # xor r9d, r9d
        stub.extend(b"\x45\x31\xc0");                                  # xor r8d, r8d
        stub.extend(b"\x31\xc9");                                      # xor ecx, ecx
        stub.extend(b"\x48\xbf" + struct.pack("<Q", main_vaddr));      # movabs rdi, main
        stub.extend(b"\x48\xb8" + struct.pack("<Q", libc_start_plt));  # movabs rax, __libc_start_main
        stub.extend(b"\xff\xd0");                                      # call rax
        stub.extend(b"\xf4");                                          # hlt
        # Patch the stub into code_bytes at the reserved offset
        code_bytes[start_stub_offset:start_stub_offset + len(stub)] = stub;
        entry_vaddr = text_vaddr + start_stub_offset;
    } else {
        entry_vaddr = text_vaddr;
        for sym in self.symbols {
            if sym.name == "_start" {
                local = local_sym_map.get("_start");
                if local is not None {
                    entry_vaddr = text_vaddr + local[1];
                }
                break;
            }
        }
    }

    # ── Assemble the ELF file ────────────────────────────────────
    output = bytearray(total_file_size);

    # ELF header
    ident = bytearray(16);
    ident[0:4] = ELFMAG;
    ident[4] = ELFCLASS64;
    ident[5] = ELFDATA2LSB;
    ident[6] = 1;  # EV_CURRENT
    ident[7] = 0;  # ELFOSABI_NONE
    struct.pack_into("16s", output, 0, bytes(ident));
    struct.pack_into(
        "<HHIQQQIHHHHHH",
        output,
        16,
        ET_EXEC,       # e_type
        EM_X86_64,     # e_machine
        1,             # e_version
        entry_vaddr,   # e_entry
        ehdr_size,     # e_phoff (right after header)
        0,             # e_shoff (no section headers needed for exec)
        0,             # e_flags
        ehdr_size,     # e_ehsize
        56,            # e_phentsize
        num_phdrs,     # e_phnum
        0,             # e_shentsize
        0,             # e_shnum
        0              # e_shstrndx
    );

    # Program headers
    phdr_off = ehdr_size;

    # PT_PHDR
    struct.pack_into(
        "<IIQQQQQQ",
        output,
        phdr_off,
        PT_PHDR,                  # p_type
        PF_R,                     # p_flags
        ehdr_size,                # p_offset
        BASE_VADDR + ehdr_size,   # p_vaddr
        BASE_VADDR + ehdr_size,   # p_paddr
        phdr_size,                # p_filesz
        phdr_size,                # p_memsz
        8                         # p_align
    );
    phdr_off += 56;

    # PT_INTERP
    struct.pack_into(
        "<IIQQQQQQ",
        output,
        phdr_off,
        PT_INTERP,          # p_type
        PF_R,               # p_flags
        interp_foff,        # p_offset
        interp_vaddr,       # p_vaddr
        interp_vaddr,       # p_paddr
        len(interp_data),   # p_filesz
        len(interp_data),   # p_memsz
        1                   # p_align
    );
    phdr_off += 56;

    # PT_LOAD (code segment - RX)
    struct.pack_into(
        "<IIQQQQQQ",
        output,
        phdr_off,
        PT_LOAD,         # p_type
        PF_R | PF_X,     # p_flags
        0,               # p_offset
        BASE_VADDR,      # p_vaddr
        BASE_VADDR,      # p_paddr
        code_seg_size,   # p_filesz
        code_seg_size,   # p_memsz
        PAGE_SIZE        # p_align
    );
    phdr_off += 56;

    # PT_LOAD (data segment - RW)
    struct.pack_into(
        "<IIQQQQQQ",
        output,
        phdr_off,
        PT_LOAD,         # p_type
        PF_R | PF_W,     # p_flags
        data_seg_foff,   # p_offset
        data_seg_vaddr,  # p_vaddr
        data_seg_vaddr,  # p_paddr
        data_seg_size,   # p_filesz
        data_seg_size,   # p_memsz
        PAGE_SIZE        # p_align
    );
    phdr_off += 56;

    # PT_DYNAMIC
    struct.pack_into(
        "<IIQQQQQQ",
        output,
        phdr_off,
        PT_DYNAMIC,            # p_type
        PF_R | PF_W,           # p_flags
        dynamic_foff,          # p_offset
        dynamic_vaddr,         # p_vaddr
        dynamic_vaddr,         # p_paddr
        len(dynamic_data),     # p_filesz
        len(dynamic_data),     # p_memsz
        8                      # p_align
    );

    # Write sections into output
    output[interp_foff:interp_foff + len(interp_data)] = interp_data;
    output[hash_foff:hash_foff + len(hash_data)] = hash_data;
    output[dynsym_foff:dynsym_foff + len(dynsym_data)] = bytes(dynsym_data);
    output[dynstr_foff:dynstr_foff + len(dynstr_data)] = dynstr_data;
    output[rela_plt_foff:rela_plt_foff + len(rela_plt_data)] = bytes(rela_plt_data);
    output[plt_foff:plt_foff + len(plt_data)] = bytes(plt_data);
    output[got_plt_foff:got_plt_foff + len(got_plt_data)] = bytes(got_plt_data);
    output[text_foff:text_foff + len(code_bytes)] = bytes(code_bytes);
    if len(rodata_bytes) > 0 {
        output[rodata_foff:rodata_foff + len(rodata_bytes)] = bytes(rodata_bytes);
    }
    output[dynamic_foff:dynamic_foff + len(dynamic_data)] = bytes(dynamic_data);
    if len(data_bytes) > 0 {
        output[data_foff:data_foff + len(data_bytes)] = bytes(data_bytes);
    }
    return bytes(output);
}


# ── Static link method ───────────────────────────────────────────
impl ElfLinker.link(
    obj_bytes: bytes, output_path: str, needed_libs: list[str] = ["libc.so.6"]
) -> bool {
    linker = ElfLinker(
        obj_data=obj_bytes,
        sections=[],
        symbols=[],
        relocations=[],
        needed_libs=needed_libs
    );
    if not linker.parse_object() {
        return False;
    }
    exe_bytes = linker.build_executable();
    if not exe_bytes {
        return False;
    }
    with open(output_path, "wb") as f {
        f.write(exe_bytes);
    }
    os.chmod(output_path, 0o755);
    return True;
}
