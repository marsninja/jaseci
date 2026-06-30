import from jaclang.runtimelib.entry_generators { register_entry_generator }

glob NATIVE_ROOT_COMPONENT_NAME = "main";

def build_registry_native_entry_script(
    entry_module: str, install_global_handlers: bool = True
) -> str {
    lines: list[str] = [
        'import { AppRegistry } from "react-native";',
        f'import {{ app as JacApp }} from "./{entry_module}.js";',
        '',
        f'AppRegistry.registerComponent({NATIVE_ROOT_COMPONENT_NAME!r}, () => JacApp);',
        ''
    ];
    return "\n".join(lines);
}

def register_native_entry_generators {
    register_entry_generator("react-native", build_registry_native_entry_script);
    register_entry_generator("native", build_registry_native_entry_script);
}
