import from typing { TypeAlias }

glob EntryGenerator: TypeAlias = Callable,
     _generators: dict[str, EntryGenerator] = {};

def register_entry_generator(target: str, fn: EntryGenerator) {
    _generators[target] = fn;
}

def get_entry_generator(target: str = "web") -> EntryGenerator {
    if target == "web" {
        _ensure_builtin_web();
    } elif target == "web:error_overlay" {
        _ensure_builtin_web_error_overlay();
    }
    fn = _generators.get(target);
    if fn is None {
        raise LookupError(
            f"No entry generator registered for target '{target}'. "
            "Is the core client framework loaded?"
        );
    }
    return fn;
}

def has_entry_generator(target: str) -> bool {
    return target in _generators;
}

def clear_entry_generators {
    _generators.clear();
}

def _build_simple_react_entry_script(
    entry_module: str, install_global_handlers: bool = True
) -> str {
    runtime_imports: list[str] = ['JacClientErrorBoundary', 'ErrorFallback'];
    if install_global_handlers {
        runtime_imports.append('__jacInstallErrorHandlers');
    }
    runtime_imports.append('__jacReactErrorHandler');

    lines: list[str] = [
        'import React from "react";',
        'import { createRoot } from "react-dom/client";',
        f'import {{ app as App }} from "./{entry_module}.js";',
        f'import {{ {", ".join(runtime_imports)} }} from "@jac/runtime";',
        ''
    ];
    if install_global_handlers {
        lines.append('__jacInstallErrorHandlers();');
    }
    lines.extend(
        [
            'const root = createRoot(document.getElementById("root"));',
            'root.render(',
            '\tReact.createElement(',
            '\t\tJacClientErrorBoundary,',
            '\t\t{ FallbackComponent: ErrorFallback, onError: __jacReactErrorHandler },',
            '\t\tReact.createElement(App, null)',
            '\t)',
            ');',
            ''
        ]
    );
    return "\n".join(lines);
}

def _build_web_error_overlay_entry_script(file_path: str, errors: str) -> str {
    return (
        'import React from "react";\n'
        'import { createRoot } from "react-dom/client";\n'
        'import { errorOverlay } from "@jac/runtime";\n'
        '\n'
        'const root = createRoot(document.getElementById("root"));\n'
        f'root.render(errorOverlay("{file_path} ", ` {errors}`), null);\n'
    );
}

def _ensure_builtin_web {
    if "web" not in _generators {
        try {
            import from jaclang.runtimelib.client.entry_generators.web_entry {
                build_simple_react_entry_script
            }
            register_entry_generator("web", build_simple_react_entry_script);
        } except ImportError {
            register_entry_generator("web", _build_simple_react_entry_script);
        }
    }
}

def _ensure_builtin_web_error_overlay {
    if "web:error_overlay" not in _generators {
        try {
            import from jaclang.runtimelib.client.entry_generators.web_entry {
                build_web_error_overlay_entry_script
            }
            register_entry_generator(
                "web:error_overlay", build_web_error_overlay_entry_script
            );
        } except ImportError {
            register_entry_generator(
                "web:error_overlay", _build_web_error_overlay_entry_script
            );
        }
    }
}
