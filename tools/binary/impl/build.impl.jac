"""Implementations for the jaclang single-binary builder (see ../build.jac)."""

import argparse;
import hashlib;
import json;
import os;
import re;
import shutil;
import struct;
import subprocess;
import tarfile;
import tempfile;
import time;
import from pathlib { Path }
import from jaclang.cli.console { console }


# ------------------------------- pbs PYTHON.json -> static link line ----------
impl load_manifest(pbs_python_dir: Path) -> dict {
    manifest = pbs_python_dir / "PYTHON.json";
    if not manifest.is_file() {
        raise SystemExit(
            f"PYTHON.json not found under {pbs_python_dir} (need a *full* pbs archive)"
        );
    }
    return dict(json.loads(manifest.read_text()));
}


impl abs_path(pbs_python_dir: Path, rel: str) -> str {
    return str((pbs_python_dir / rel).resolve());
}


impl builtin_module_names(pbs_python_dir: Path, manifest: any) -> (set | None) {
    src = manifest["build_info"].get("inittab_source");
    if not src {
        return None;
    }
    path = pbs_python_dir / str(src);
    if not path.is_file() {
        return None;
    }
    names: set = set();
    # Inittab lines look like:  {"_ssl", PyInit__ssl},
    for mt in re.finditer('\\{"([A-Za-z_][A-Za-z0-9_.]*)"\\s*,', path.read_text()) {
        names.add(mt.group(1));
    }
    # Empty => treat as "no inittab info" (None) so callers link all, not none.
    if not names {
        return None;
    }
    return names;
}


impl collect_link_inputs(pbs_python_dir: Path) -> dict {
    pbs_python_dir = pbs_python_dir.resolve();
    m: any = load_manifest(pbs_python_dir);
    bi: any = m["build_info"];
    core: any = bi["core"];

    include_dir = abs_path(pbs_python_dir, str(m["python_paths"]["include"]));

    objects: list = [];
    static_libs: list = [];
    system_libs: list = [];

    # --- core --------------------------------------------------------------
    core_lib = abs_path(pbs_python_dir, str(core["static_lib"]));
    if core_lib not in static_libs {
        static_libs.append(core_lib);
    }
    for lk in core.get("links", []) {
        if lk.get("system") {
            if lk["name"] not in system_libs {
                system_libs.append(lk["name"]);
            }
        } elif lk.get("path_static") {
            p = abs_path(pbs_python_dir, str(lk["path_static"]));
            if p not in static_libs {
                static_libs.append(p);
            }
        } elif lk["name"] not in system_libs {
            system_libs.append(lk["name"]);
        }
    }

    # The generated inittab object registers every built-in PyInit_*; linking it
    # pins which extension objects must also be present.
    inittab = bi.get("inittab_object");
    if inittab {
        objects.append(abs_path(pbs_python_dir, str(inittab)));
    }

    # --- extensions --------------------------------------------------------
    # Link ONLY the built-in set (those in the inittab); shared-library
    # extensions like _tkinter are excluded. in_core extensions are already
    # inside libpython3.12.a, so we take only their external links, never their
    # objects (avoids duplicate symbols).
    builtins = builtin_module_names(pbs_python_dir, m);
    exts: any = bi.get("extensions", {});
    for name in sorted(list(exts.keys())) {
        variants = exts[name];
        if not variants {
            continue;
        }
        v: any = variants[0];
        # Skip shared-library extensions (flagged by a shared_lib artifact or
        # simply absent from the built-in inittab).
        if "shared_lib" in v {
            continue;
        }
        if builtins is not None {
            if name not in builtins {
                continue;
            }
        }
        if not v.get("in_core", False) {
            for obj in v.get("objs", []) {
                p2 = abs_path(pbs_python_dir, str(obj));
                if p2 not in objects {
                    objects.append(p2);
                }
            }
        }
        for lk in v.get("links", []) {
            if lk.get("system") {
                if lk["name"] not in system_libs {
                    system_libs.append(lk["name"]);
                }
            } elif lk.get("path_static") {
                p3 = abs_path(pbs_python_dir, str(lk["path_static"]));
                if p3 not in static_libs {
                    static_libs.append(p3);
                }
            } elif lk["name"] not in system_libs {
                # No static variant shipped; fall back to a system -l.
                system_libs.append(lk["name"]);
            }
        }
    }

    # libm is universally required and not always listed explicitly.
    if "m" not in system_libs {
        system_libs.append("m");
    }

    return {
        "include_dir": include_dir,
        "objects": objects,
        "static_libs": static_libs,
        "system_libs": system_libs,
        "cflags": bi.get("inittab_cflags", []),

    };
}


impl build_link_command(
    pbs_python_dir: Path,
    launcher_obj: str,
    output: str,
    cc: str = "cc",
    extra_objects: (list | None) = None,
    extra_libraries: (list | None) = None,
    extra_ldflags: (list | None) = None
) -> list {
    inp: any = collect_link_inputs(pbs_python_dir);

    argv: list = [cc, "-Os", str(launcher_obj)];
    if extra_objects {
        argv += extra_objects;
    }
    argv += list(inp["objects"]);

    # Archives go in a group: libpython references extension symbols and vice
    # versa, so single-pass resolution would otherwise drop symbols.
    argv += ["-Wl,--start-group"];
    argv += list(inp["static_libs"]);
    if extra_libraries {
        argv += extra_libraries;
    }
    argv += ["-Wl,--end-group"];

    # Export libpython symbols so any in-process extension init can find them.
    argv += ["-Wl,-export-dynamic"];
    if extra_ldflags {
        argv += extra_ldflags;
    }

    for name in list(inp["system_libs"]) {
        argv += [f"-l{name}"];
    }
    argv += ["-o", output];
    return argv;
}


impl compile_launcher_command(
    pbs_python_dir: Path,
    launcher_c: str,
    obj_out: str,
    cc: str = "cc",
    zstd_include: (str | None) = None
) -> list {
    inp: any = collect_link_inputs(pbs_python_dir);
    # -Wno-format-truncation: snprintf into PATH_MAX buffers trips gcc's
    # worst-case truncation heuristic; real cache/extract paths never overflow.
    argv: list = [
        cc,
        "-Os",
        "-std=c11",
        "-Wall",
        "-Wno-format-truncation",
        "-c",
        str(launcher_c),
        "-I",
        str(inp["include_dir"])
    ];
    if zstd_include {
        argv += ["-I", zstd_include];
    }
    argv += ["-o", obj_out];
    return argv;
}


# ------------------------------- build pipeline ------------------------------
impl log(msg: str) {
    console.print(f"[build] {msg}");
}


impl run(argv: list, env: (dict | None) = None) {
    log("$ " + " ".join([str(a) for a in argv]));
    subprocess.run(argv, check=True, env=env);
}


impl pbs_python(pbs_dir: Path) -> Path {
    p = pbs_dir / "install" / "bin" / "python3";
    if not p.exists() {
        p = pbs_dir / "install" / "bin" / "python3.12";
    }
    if not p.exists() {
        raise SystemExit(f"pbs interpreter not found under {pbs_dir}/install/bin");
    }
    return p;
}


impl fetch_pbs(workdir: Path, archive: (Path | None)) -> Path {
    a: Path = workdir / PBS_ASSET;
    if archive is not None {
        a = archive.resolve();
        log(f"using local pbs archive {a}");
    } else {
        url = f"https://github.com/astral-sh/python-build-standalone/releases/download/{PBS_TAG}/{PBS_ASSET}";
        if not a.exists() {
            log(f"downloading {url}");
            run(["curl", "-fsSL", "-o", str(a), url]);
        }
    }

    dest = workdir / "pbs";
    if dest.exists() {
        shutil.rmtree(dest);
    }
    dest.mkdir(parents=True);
    log(f"extracting {a.name}");
    # zstd is not in the 3.12 stdlib, so decompress via the CLI for .zst archives.
    if str(a.name).endswith(".zst") {
        plain = workdir / "pbs.tar";
        run(["zstd", "-d", "-f", "-q", str(a), "-o", str(plain)]);
        with tarfile.open(plain, mode="r:") as tf {
            tf.extractall(dest);
        }
        plain.unlink();
    } else {
        with tarfile.open(a, mode="r:*") as tf {
            tf.extractall(dest);
        }
    }
    py = dest / "python";
    if not (py / "PYTHON.json").is_file() {
        raise SystemExit(
            "extracted archive is not a pbs *full* archive (no PYTHON.json)"
        );
    }
    return py;
}


impl populate_site(pbs_dir: Path, site: Path, jaclang_spec: str) {
    if site.exists() {
        shutil.rmtree(site);
    }
    site.mkdir(parents=True);
    py = pbs_python(pbs_dir);
    run([str(py), "-m", "ensurepip", "--upgrade"]);
    run([str(py), "-m", "pip", "install", "--upgrade", "pip"]);
    run([str(py), "-m", "pip", "install", jaclang_spec, "--target", str(site)]);

    # _jac_finder is a top-level py-module shipped in the wheel; confirm it landed.
    if not (site / "_jac_finder.py").is_file() {
        raise SystemExit(
            "_jac_finder.py missing from installed site (wheel layout changed?)"
        );
    }

    # Strip build-time tooling -- never needed at runtime.
    patterns: list[str] = [
        "pip",
        "pip-*",
        "setuptools",
        "setuptools-*",
        "pkg_resources",
        "_distutils_hack",
        "*.dist-info/RECORD"
    ];
    for pat in patterns {
        for p in site.glob(pat) {
            if p.is_dir() {
                shutil.rmtree(p, ignore_errors=True);
            } else {
                p.unlink(missing_ok=True);
            }
        }
    }
    log(f"site populated: {len(list(site.rglob('*')))} entries");
}


impl generate_precompiled(pbs_dir: Path, site: Path) {
    py = pbs_python(pbs_dir);
    precompile = site / "jaclang" / "utils" / "precompile_bytecode.jac";
    if not precompile.is_file() {
        raise SystemExit(f"precompile script missing: {precompile}");
    }
    boot = (
        "import sys\n" + f"sys.path.insert(0, {str(site)!r})\n" + "import _jac_finder; _jac_finder.install()\n" + f"sys.argv = ['jac', 'run', {str(
            precompile
        )!r}, {str(site)!r}]\n" + "from jaclang.jac0core.cli_boot import start_cli\n" + "start_cli()\n"
    );
    # Isolated env so the build host's caches/plugins can't leak in.
    env: dict = {"PATH": "/usr/bin:/bin", "HOME": str(site.parent)};
    run([str(py), "-S", "-c", boot], env=env);
    out = site / "jaclang" / "_precompiled";
    jirs: list = list(out.rglob("*.jir")) if out.exists() else [];
    if not jirs {
        raise SystemExit("precompile produced no .jir files");
    }
    log(f"_precompiled: {len(jirs)} JIR files generated");
}


impl stage_runtime(pbs_dir: Path, site: Path, stage: Path) {
    if stage.exists() {
        shutil.rmtree(stage);
    }
    (stage / "python" / "lib").mkdir(parents=True);

    src_stdlib = pbs_dir / "install" / "lib" / "python3.12";
    dst_stdlib = stage / "python" / "lib" / "python3.12";
    shutil.copytree(src_stdlib, dst_stdlib, symlinks=True);

    for name in STDLIB_PRUNE {
        victim = dst_stdlib / name;
        if victim.is_dir() {
            shutil.rmtree(victim, ignore_errors=True);
        } elif victim.exists() {
            victim.unlink();
        }
    }
    # Drop the build config dir (Makefile, static libs, headers): build-time only.
    for cfg in dst_stdlib.glob("config-*") {
        shutil.rmtree(cfg, ignore_errors=True);
    }

    shutil.copytree(site, stage / "site", symlinks=True);

    # Hash-pin every .pyc so startup never depends on file mtimes (our tar does
    # not preserve them) and never recompiles the shipped stdlib/site.
    py = pbs_python(pbs_dir);
    run(
        [
            str(py),
            "-m",
            "compileall",
            "-q",
            "-f",
            "--invalidation-mode",
            "unchecked-hash",
            str(stage / "python" / "lib" / "python3.12"),
            str(stage / "site")
        ]
    );
    log(f"runtime staged at {stage}");
}


impl pack_payload(stage: Path, out_zst: Path) -> tuple {
    tar_path = out_zst.with_suffix(".tar");
    if tar_path.exists() {
        tar_path.unlink();
    }
    with tarfile.open(str(tar_path), "w") as tf {
        # GNU format (== tarfile.GNU_FORMAT) keeps long-name handling simple for
        # the C untar reader. Use the literal so the typed stub accepts it.
        tf.format = 1;
        # Store paths relative to stage so they extract straight into rt/<hash>/.
        for child in sorted(list(stage.iterdir())) {
            tf.add(child, arcname=child.name, recursive=True);
        }
    }
    run(["zstd", "-19", "-T0", "-f", "-q", str(tar_path), "-o", str(out_zst)]);
    tar_path.unlink();
    data = out_zst.read_bytes();
    digest = hashlib.sha256(data).hexdigest();
    log(f"payload packed: {len(data) // 1024} KiB, sha256={digest[:16]}...");
    return (len(data), digest);
}


impl find_static_zstd(pbs_dir: Path) -> (str | None) {
    candidates: list[Path] = [
        pbs_dir / "build" / "lib" / "libzstd.a",
        Path("/usr/lib/x86_64-linux-gnu/libzstd.a"),
        Path("/usr/lib64/libzstd.a"),
        Path("/usr/local/lib/libzstd.a"),
        Path("/usr/lib/libzstd.a")
    ];
    for c in candidates {
        if c.is_file() {
            return str(c);
        }
    }
    return None;
}


impl link_stub(pbs_dir: Path, stub_out: Path) {
    cc = str(os.environ.get("CC", "cc"));
    td = tempfile.mkdtemp();
    try {
        obj_path = Path(td) / "launcher.o";
        run(compile_launcher_command(pbs_dir, str(LAUNCHER_C), str(obj_path), cc=cc));
        # Link libzstd statically so the binary is self-contained (libzstd is
        # not in the manylinux2014 allowlist). Prefer a pbs-shipped lib, then a
        # system static lib; fall back to dynamic only as a last resort.
        zstd_a = find_static_zstd(pbs_dir);
        extra_libs: list = [];
        if zstd_a {
            extra_libs = [zstd_a];
        } else {
            log(
                "WARNING: no static libzstd.a found; linking libzstd dynamically "
                "(binary will depend on libzstd.so.1 at runtime)"
            );
            extra_libs = ["-lzstd"];
        }
        run(
            build_link_command(
                pbs_dir, str(obj_path), str(stub_out), cc=cc, extra_libraries=extra_libs
            )
        );
    } finally {
        shutil.rmtree(td, ignore_errors=True);
    }
    # Strip to shrink the (large) static binary.
    subprocess.run(["strip", str(stub_out)], check=False);
    log(f"stub linked: {stub_out.stat().st_size // 1024 // 1024} MiB");
}


impl concat_binary(
    stub: Path, payload: Path, payload_len: int, digest: str, out: Path
) {
    trailer = "JACBIN01".encode("ascii") + struct.pack("<Q", payload_len) + digest.encode(
        "ascii"
    );
    if len(trailer) != (8 + 8 + 64) {
        raise SystemExit(f"bad trailer length {len(trailer)}");
    }
    with out.open("wb") as f {
        f.write(stub.read_bytes());
        f.write(payload.read_bytes());
        f.write(trailer);
    }
    out.chmod(0o755);
    log(f"binary written: {out} ({out.stat().st_size // 1024 // 1024} MiB)");
}


impl jac_invoke(binary: Path, env: dict, args: list, timeout: int = 120) -> str {
    cp = subprocess.run(
        [str(binary)] + args, env=env, capture_output=True, text=True, timeout=timeout
    );
    if cp.returncode != 0 {
        argstr = " ".join([str(a) for a in args]);
        raise SystemExit(
            f"smoke FAILED: jac {argstr}\n--stdout--\n{cp.stdout}\n--stderr--\n{cp.stderr}"
        );
    }
    return cp.stdout;
}


impl smoke_test(binary: Path) {
    td = tempfile.mkdtemp();
    try {
        cache = Path(td) / "cache";
        hello = Path(td) / "hello.jac";
        hello.write_text('with entry { print("hello from binary"); }\n');
        obj_file = Path(td) / "obj.jac";
        obj_file.write_text(
            "obj P { has x: int = 0; def sq -> int { return self.x * self.x; } }\n" + "with entry { print(P(x=7).sq()); print([i*i for i in range(4)]); }\n"
        );
        # A deliberately minimal environment (no system Python on PATH).
        env: dict = {
            "PATH": "/usr/bin:/bin",
            "HOME": str(td),
            "XDG_CACHE_HOME": str(cache)
        };

        log("smoke: jac --version");
        console.print(jac_invoke(binary, env, ["--version"]).strip());

        t0 = time.monotonic();
        out = jac_invoke(binary, env, ["run", str(hello)]);
        cold = time.monotonic() - t0;
        if "hello from binary" not in out {
            raise SystemExit(f"unexpected hello output: {out}");
        }
        log(f"smoke: cold `jac run hello` = {cold:.2f}s  -> {out.strip()!r}");

        t0 = time.monotonic();
        out = jac_invoke(binary, env, ["run", str(hello)]);
        warm = time.monotonic() - t0;
        log(f"smoke: warm `jac run hello` = {warm:.2f}s");

        out = jac_invoke(binary, env, ["run", str(obj_file)]);
        if ("49" not in out) or ("[0, 1, 4, 9]" not in out) {
            raise SystemExit(f"unexpected obj output: {out}");
        }
        log(f"smoke: obj/comprehension -> {out.strip()!r}");

        # Hermeticity: all writes land under XDG_CACHE_HOME.
        if not (cache.exists() and (len(list(cache.rglob("*"))) > 0)) {
            raise SystemExit("no cache was written");
        }
        log("smoke: PASS (clean-env run, writes confined to cache)");
    } finally {
        shutil.rmtree(td, ignore_errors=True);
    }
}


impl main -> int {
    parser = argparse.ArgumentParser();
    # Path-valued options are parsed as strings and wrapped in Path() below;
    # argparse's `type=Path` is rejected by the typed stub.
    parser.add_argument("--pbs-archive", help="local pbs full archive (skip download)");
    g = parser.add_mutually_exclusive_group(required=True);
    g.add_argument(
        "--jaclang-version", help="jaclang version to pip install (e.g. 0.16.7)"
    );
    g.add_argument("--jaclang-path", help="local jaclang source dir to pip install");
    parser.add_argument("--output", required=True, help="output binary path");
    parser.add_argument("--workdir", help="scratch dir (default: temp)");
    parser.add_argument(
        "--keep", action="store_true", help="keep the workdir for inspection"
    );
    parser.add_argument("--no-smoke", action="store_true", help="skip the smoke test");
    args = parser.parse_args();

    workdir: Path = Path(str(args.workdir))
        if args.workdir
        else Path(tempfile.mkdtemp(prefix="jacbuild-"));
    workdir.mkdir(parents=True, exist_ok=True);
    log(f"workdir = {workdir}");

    jaclang_spec: str = "";
    if args.jaclang_path {
        jaclang_spec = str(Path(str(args.jaclang_path)).resolve());
    } else {
        jaclang_spec = f"jaclang=={args.jaclang_version}";
    }

    pbs_archive: (Path | None) = Path(str(args.pbs_archive))
        if args.pbs_archive
        else None;
    output: Path = Path(str(args.output));

    try {
        pbs_dir = fetch_pbs(workdir, pbs_archive);
        site = workdir / "site";
        populate_site(pbs_dir, site, jaclang_spec);
        generate_precompiled(pbs_dir, site);
        stage = workdir / "stage";
        stage_runtime(pbs_dir, site, stage);
        payload = workdir / "runtime.tar.zst";
        res = pack_payload(stage, payload);
        plen: int = int(res[0]);
        digest: str = str(res[1]);
        stub = workdir / "jac.stub";
        link_stub(pbs_dir, stub);
        output.parent.mkdir(parents=True, exist_ok=True);
        concat_binary(stub, payload, plen, digest, output);
        # Emit checksum alongside the binary.
        sha = hashlib.sha256(output.read_bytes()).hexdigest();
        (output.parent / (output.name + ".sha256")).write_text(
            f"{sha}  {output.name}\n"
        );
        log(f"sha256({output.name}) = {sha}");
        if not args.no_smoke {
            smoke_test(output);
        }
    } finally {
        if (not args.keep) and (args.workdir is None) {
            shutil.rmtree(workdir, ignore_errors=True);
        }
    }

    log("DONE");
    return 0;
}
