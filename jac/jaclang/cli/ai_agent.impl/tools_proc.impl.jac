import os;
import re;
import sys;
import time;
import signal;
import subprocess;
import from pathlib { Path }

impl ProcessTools._proc_output(result: any) -> str {
    combined = (str(result.stdout or "") + str(result.stderr or "")).strip();
    return truncate(combined or f"(no output; exit code {result.returncode})");
}

impl ProcessTools.run_jac_cli(subcommand: str, path: str) -> str {
    try {
        return self._proc_output(
            subprocess.run(
                [sys.executable, "-m", "jaclang", subcommand, path],
                capture_output=True,
                text=True,
                timeout=120,
                cwd=self.ws.cwd or None
            )
        );
    } except Exception as e {
        return f"ERROR running `jac {subcommand} {path}`: {e}";
    }
}

sem ProcessTools.run_command = "Run a shell command in the project directory and return its combined output. Use this to scaffold a new project (`jac create --kind web-app <name>`), install dependencies (`jac install`), run a file (`jac run <file>`), run tests, or any other shell task. `jac create --kind <kind>` kinds: cli (default), web-app, service, native-binary, py-package, and more (run `jac create --list_jacpacks` for the full list).";
sem ProcessTools.run_command.command = "The shell command to run.";
impl ProcessTools.run_command(command: str) -> str {
    stripped = command.strip();
    if re.search("\\bjac\\s+(start|serve)\\b", stripped) and "--help" not in stripped {
        return (
            "Don't start the server with run_command -- it blocks. Use the "
            "serve(entry_file) tool instead: it launches the dev server, waits "
            "until it is actually ready, and returns the URL to browse_open. "
            "Then exercise the page and call stop_server when done."
        );
    }
    if not confirm(f"run shell command: {command}") {
        return "DENIED: the user declined to run this command.";
    }

    env = dict(os.environ);
    bin_dir = os.path.dirname(sys.executable);
    if bin_dir {
        env["PATH"] = bin_dir + os.pathsep + env.get("PATH", "");
    }
    work_dir = self.ws.cwd or os.getcwd();

    marker = "__JAC_AI_CWD__";
    wrapped = (
        command + f"\n__jac_ai_rc=$?\nprintf '\\n{marker}%s\\n' \"$(pwd)\"\n"
        "exit $__jac_ai_rc"
    );
    try {
        result = subprocess.run(
            wrapped,
            shell=True,
            capture_output=True,
            text=True,
            timeout=180,
            env=env,
            cwd=work_dir
        );
    } except subprocess.TimeoutExpired {
        return f"ERROR: `{command}` timed out after 180s.";
    } except Exception as e {
        return f"ERROR running `{command}`: {e}";
    }
    stdout = str(result.stdout or "");
    new_cwd = "";
    kept: list[str] = [];
    for ln in stdout.splitlines() {
        if ln.startswith(marker) {
            new_cwd = ln[len(marker):].strip();
        } else {
            kept.append(ln);
        }
    }
    if new_cwd and new_cwd != work_dir {
        self.ws.set_cwd(new_cwd);
    }
    combined = ("\n".join(kept) + str(result.stderr or "")).strip();
    out = truncate(combined or f"(no output; exit code {result.returncode})");

    if new_cwd and new_cwd != work_dir {
        out = f"(now in {new_cwd})\n" + out;
    }
    return out;
}

sem ProcessTools.jac_check = "Type-check and compile Jac code with `jac check`. Pass a single file, or a directory (`.` for the whole project) to check everything at once. Use this after writing or editing Jac code to confirm it is valid.";
sem ProcessTools.jac_check.path = "File or directory to check; '.' or empty string checks the whole project.";
impl ProcessTools.jac_check(path: str) -> str {
    return self.run_jac_cli("check", path or ".");
}

sem ProcessTools.start_app = "Start the app with `jac start` for ~12 seconds to confirm it boots, then stop it; returns the startup logs. Use this after building an app to catch errors that `jac check` cannot.";
sem ProcessTools.start_app.entry_file = "Entry .jac file to start; empty string means 'main.jac'.";
impl ProcessTools.start_app(entry_file: str) -> str {
    entry_path = entry_file or "main.jac";
    abs_entry = self.ws.resolve(entry_path);
    if not os.path.isfile(abs_entry) {
        return (
            f"ERROR: no such entry file '{entry_path}' (looked in "
            f"{self.ws.cwd or os.getcwd()}). Use list_dir to find the app's "
            "main .jac file, then pass its path."
        );
    }
    if not confirm(f"start the app with `jac start {entry_path}`") {
        return "DENIED: the user declined to start the app.";
    }

    work_dir = os.path.dirname(abs_entry) or ".";
    target = os.path.basename(abs_entry);
    try {
        proc = subprocess.Popen(
            [sys.executable, "-m", "jaclang", "start", target],
            cwd=work_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        );
    } except Exception as e {
        return f"ERROR launching `jac start {entry_path}`: {e}";
    }

    boot_wait = 12.0;
    try {
        raw = os.environ.get("JAC_AI_START_TIMEOUT");
        if raw {
            boot_wait = float(raw);
        }
    } except Exception as e {
        _ = e;
    }
    time.sleep(boot_wait);
    proc.terminate();
    try {
        output = proc.communicate(timeout=10)[0];
    } except Exception {
        proc.kill();
        output = proc.communicate()[0];
    }
    return truncate(str(output) if output else "(no startup output)");
}

sem ProcessTools.serve = "Start the web/full-stack dev server and wait until it is actually serving, returning the URL to open. The first start can take a while because it installs the client dependencies and builds the client; this tool blocks until the server is ready (or fails) so you do not have to guess. On success, call browse_open on the returned URL. On failure it returns the server log tail -- read it, go back to Build to fix the cause, and do not conclude the app works.";
sem ProcessTools.serve.entry_file = "Entry .jac file to serve; empty string means 'main.jac'.";

impl ProcessTools.serve(entry_file: str) -> str {
    entry_path = entry_file or "main.jac";
    abs_entry = self.ws.resolve(entry_path);
    if not os.path.isfile(abs_entry) {
        return (
            f"ERROR: no such entry file '{entry_path}' (looked in "
            f"{self.ws.cwd or os.getcwd()}). Use list_dir to find the app's "
            "main .jac file (the one with the `cl`/`sv` mount), then pass its path."
        );
    }
    if not confirm(f"start the dev server with `jac start {entry_path}`") {
        return "DENIED: the user declined to start the server.";
    }

    self._serve_shutdown();
    work_dir = os.path.dirname(abs_entry) or ".";
    target = os.path.basename(abs_entry);
    log_path = "/tmp/jac_ai_serve.log";
    try {
        log_f = open(log_path, "w", encoding="utf-8");

        self.serve_proc = subprocess.Popen(
            [sys.executable, "-m", "jaclang", "start", target],
            cwd=work_dir,
            stdout=log_f,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True
        );

        log_f.close();
    } except Exception as e {
        return f"ERROR launching `jac start {entry_path}`: {e}";
    }

    timeout = 120.0;
    try {
        raw = os.environ.get("JAC_AI_SERVE_TIMEOUT");
        if raw {
            timeout = float(raw);
        }
    } except Exception as e {
        _ = e;
    }

    url_re = re.compile(
        "https?://(?:localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0)(?::\\d+)?\\S*"
    );
    deadline = time.time() + timeout;
    url = "";
    while time.time() < deadline {
        if self.serve_proc.poll() is not None {
            break;
        }
        try {
            log_text = Path(log_path).read_text();
        } except Exception {
            log_text = "";
        }
        m = url_re.search(log_text);
        if m {
            url = m.group(0).rstrip("/");
            break;
        }
        time.sleep(1.0);
    }
    if url {
        return (
            f"OK: server ready at {url} (logs: {log_path}). "
            f"Open it with browse_open(\"{url}\"), exercise it, then stop_server."
        );
    }
    tail = "";
    try {
        tail = "\n".join(Path(log_path).read_text().splitlines()[-25:]);
    } except Exception {
        tail = "(no log output)";
    }
    self._serve_shutdown();
    return (
        f"ERROR: the server did not become ready within {int(timeout)}s. "
        f"Last log lines:\n{tail}"
    );
}

sem ProcessTools.stop_server = "Stop the dev server started by serve. Call this when finished with browser QA.";

impl ProcessTools.stop_server -> str {
    self._serve_shutdown();
    return "OK: dev server stopped.";
}

impl ProcessTools._serve_shutdown{
    if self.serve_proc is not None {
        try {
            if hasattr(os, "killpg") {
                os.killpg(os.getpgid(int(self.serve_proc.pid)), int(signal.SIGTERM));
            } else {
                self.serve_proc.terminate();
            }
        } except Exception {
            try {
                self.serve_proc.terminate();
            } except Exception { }
        }
        try {
            self.serve_proc.wait(timeout=5);
        } except Exception {
            try {
                self.serve_proc.kill();
            } except Exception { }
        }
        self.serve_proc = None;
    }
}
