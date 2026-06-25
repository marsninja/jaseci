"""sv<->na equivalence: zlib.

Same `import from zlib { ... }` binds CPython on sv and na_stdlib/zlib.na.jac
(a thin FFI surface over libz) on na. Pins compress (byte-identical, asserted via
crc32 of the compressed stream), decompress round-trip, and crc32/adler32 with and
without a continuation seed. Only int results are digested (bytes do not need to
cross the boundary).
"""
import from zlib { compress, decompress, crc32, adler32 }

def _diff(label: str, want: str, got: str) -> int {
    wl = want.split("\n");
    gl = got.split("\n");
    n = len(wl) if len(wl) > len(gl) else len(gl);
    bad = 0;
    for i in range(n) {
        w = wl[i] if i < len(wl) else "<none>";
        g = gl[i] if i < len(gl) else "<none>";
        if w != g {
            print(f"  [FAIL] {label}: sv={repr(w)} na={repr(g)}");
            bad += 1;
        }
    }
    status = "OK" if bad == 0 else "MISMATCH";
    print(f"{label}: {n - bad}/{n} lines match -- {status}");
    return bad;
}

def _dec(x: any) -> str {
    if isinstance(x, bytes) { return x.decode("utf-8", "surrogatepass"); }
    return x as str;
}

sv {
    def zlib_sv() -> str {
        data = b"hello world, hello world, hello zlib zlib zlib!";
        comp = compress(data, 6);
        back = decompress(comp);
        empty_rt = decompress(compress(b"", 6));
        p: list[str] = [];
        p.append("crc_basic=" + str(crc32(b"hello")));
        p.append("crc_seed=" + str(crc32(b"world", crc32(b"hello"))));
        p.append("crc_empty=" + str(crc32(b"")));
        p.append("adler_basic=" + str(adler32(b"hello")));
        p.append("adler_seed=" + str(adler32(b"world", adler32(b"hello"))));
        p.append("comp_crc=" + str(crc32(comp)));
        p.append("comp_smaller=" + str(1 if len(comp) < len(data) else 0));
        p.append("roundtrip_ok=" + str(1 if back == data else 0));
        p.append("roundtrip_len=" + str(len(back)));
        p.append("decomp_crc=" + str(crc32(back)));
        p.append("empty_ok=" + str(1 if empty_rt == b"" else 0));
        return "\n".join(p);
    }
}

na {
    def zlib_na() -> str {
        data = b"hello world, hello world, hello zlib zlib zlib!";
        comp = compress(data, 6);
        back = decompress(comp);
        empty_rt = decompress(compress(b"", 6));
        p: list[str] = [];
        p.append("crc_basic=" + str(crc32(b"hello")));
        p.append("crc_seed=" + str(crc32(b"world", crc32(b"hello"))));
        p.append("crc_empty=" + str(crc32(b"")));
        p.append("adler_basic=" + str(adler32(b"hello")));
        p.append("adler_seed=" + str(adler32(b"world", adler32(b"hello"))));
        p.append("comp_crc=" + str(crc32(comp)));
        p.append("comp_smaller=" + str(1 if len(comp) < len(data) else 0));
        p.append("roundtrip_ok=" + str(1 if back == data else 0));
        p.append("roundtrip_len=" + str(len(back)));
        p.append("decomp_crc=" + str(crc32(back)));
        p.append("empty_ok=" + str(1 if empty_rt == b"" else 0));
        return "\n".join(p);
    }
}

with entry {
    bad = _diff("zlib", zlib_sv(), _dec(zlib_na()));
    assert bad == 0, f"zlib: {bad} mismatch(es)";
}
