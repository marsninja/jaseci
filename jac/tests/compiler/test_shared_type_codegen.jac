"""Tests for shared type code generation — cross-boundary archetype emission."""

import os;
import tempfile;
import from pathlib { Path }
import from tempfile { NamedTemporaryFile, TemporaryDirectory }
import jaclang;
import from jaclang.jac0core.program { JacProgram }

glob _test_tmp_dir: str = tempfile.mkdtemp(prefix="jac_test_shared_types_");

"""Write inline Jac code to a temp file and compile it, return the module."""
def compile_inline(code: str, prog: JacProgram | None = None) -> object {
    with NamedTemporaryFile(
        mode="w", suffix=".jac", delete=False, dir=_test_tmp_dir
    ) as f {
        f.write(code);
        f.flush();
        if prog is None {
            prog = JacProgram();
        }
        mod = prog.compile(f.name);
        os.unlink(f.name);
        return mod;
    }
}

# =============================================================================
# Phase 1: Shared types emitted as JS classes with registration
# =============================================================================
test "shared types emit JS class and registration for cross-boundary returns" {
    prog = JacProgram();

    code = '"""Test shared type codegen."""\n\nobj UserProfile {\n    has name: str, age: int;\n}\n\nobj Address {\n    has street: str, city: str;\n}\n\nobj DetailedUser {\n    has profile: UserProfile, address: Address;\n}\n\nsv def:pub getUser(id: str) -> UserProfile {\n    return UserProfile(name="Alice", age=30);\n}\n\nsv def:pub getDetailed(id: str) -> DetailedUser {\n    return DetailedUser(\n        profile=UserProfile(name="Bob", age=25),\n        address=Address(street="123 Main", city="NYC")\n    );\n}\n\ncl {\n    async def showUser() -> Any {\n        user = await getUser("123");\n        detailed = await getDetailed("456");\n        return <div>{user.name}</div>;\n    }\n}\n';
    mod = compile_inline(code, prog);
    js = mod.gen.js;

    # Shared archetype classes should be emitted to JS
    assert "class UserProfile" in js , "UserProfile should be emitted as JS class";
    assert "class Address" in js , "Address should be emitted as JS class";
    assert "class DetailedUser" in js , "Nested shared type DetailedUser should be emitted as JS class";

    # Registration calls should be present
    assert '__jacRegisterType("UserProfile", UserProfile)' in js , "UserProfile should be registered in type registry";
    assert '__jacRegisterType("Address", Address)' in js , "Address should be registered in type registry";
    assert '__jacRegisterType("DetailedUser", DetailedUser)' in js , "DetailedUser should be registered in type registry";

    # __jacRegisterType should be imported from runtime
    assert "__jacRegisterType" in js;
    assert '@jac/runtime' in js;

    # __jacCallFunction should still be used for the server calls
    assert '__jacCallFunction("getUser"' in js;
    assert '__jacCallFunction("getDetailed"' in js;
}

test "shared types populate client manifest shared_types" {
    prog = JacProgram();

    code = '"""Test manifest population."""\n\nobj UserProfile {\n    has name: str, age: int;\n}\n\nsv def:pub getUser(id: str) -> UserProfile {\n    return UserProfile(name="Alice", age=30);\n}\n\ncl {\n    async def app() -> Any {\n        user = await getUser("1");\n        return <div>{user.name}</div>;\n    }\n}\n';
    mod = compile_inline(code, prog);
    manifest = mod.gen.client_manifest;

    # shared_types in manifest should be populated
    assert "UserProfile" in manifest.shared_types , "UserProfile should be in shared_types manifest";

    st = manifest.shared_types["UserProfile"];
    assert st.name == "UserProfile";
    field_names = [f[0] for f in st.fields];
    assert "name" in field_names , "UserProfile should have 'name' field info";
    assert "age" in field_names , "UserProfile should have 'age' field info";
}

# =============================================================================
# Phase 2: Non-cross-boundary archetypes stay server-only
# =============================================================================
test "server-only archetypes are NOT emitted to JS" {
    prog = JacProgram();

    code = '"""Test server-only types stay server-only."""\n\nobj ServerOnly {\n    has secret: str;\n}\n\nsv def:pub getData() -> dict {\n    return {"key": "value"};\n}\n\ncl {\n    async def app() -> Any {\n        data = await getData();\n        return <div>{data}</div>;\n    }\n}\n';
    mod = compile_inline(code, prog);
    js = mod.gen.js;

    # ServerOnly is never returned across boundary, should NOT be in JS
    assert "class ServerOnly" not in js , "Server-only archetype should not appear in JS output";
    assert '__jacRegisterType("ServerOnly"' not in js , "Server-only archetype should not have registration call";
}

# =============================================================================
# Phase 3: JS class constructor structure
# =============================================================================
test "shared type JS class has constructor with field assignment" {
    prog = JacProgram();

    code = '"""Test constructor generation."""\n\nobj Item {\n    has name: str, qty: int;\n}\n\nsv def:pub getItem() -> Item {\n    return Item(name="Widget", qty=5);\n}\n\ncl {\n    async def app() -> Any {\n        item = await getItem();\n        return <div>{item.name}: {item.qty}</div>;\n    }\n}\n';
    mod = compile_inline(code, prog);
    js = mod.gen.js;

    # Class should have a constructor that assigns fields from props
    assert "class Item" in js;
    assert "constructor" in js , "JS class should have a constructor";
    assert "this.name" in js , "Constructor should assign name field";
    assert "this.qty" in js , "Constructor should assign qty field";
}

# =============================================================================
# Phase 4: Shared types are exported
# =============================================================================
test "shared types appear in JS exports" {
    prog = JacProgram();

    code = '"""Test export."""\n\nobj Profile {\n    has name: str;\n}\n\nsv def:pub getProfile() -> Profile {\n    return Profile(name="Test");\n}\n\ncl {\n    async def app() -> Any {\n        p = await getProfile();\n        return <div>{p.name}</div>;\n    }\n}\n';
    mod = compile_inline(code, prog);
    js = mod.gen.js;
    manifest = mod.gen.client_manifest;

    # Shared types should be in the export list
    assert "Profile" in manifest.exports , "Profile should be in client manifest exports";
    assert "export" in js , "JS should have export statement";
}

# =============================================================================
# Phase 5: Multiple functions sharing the same return type
# =============================================================================
test "same shared type used by multiple functions generates single class" {
    prog = JacProgram();

    code = '"""Test dedup."""\n\nobj Item {\n    has name: str;\n}\n\nsv def:pub getItem1() -> Item {\n    return Item(name="A");\n}\n\nsv def:pub getItem2() -> Item {\n    return Item(name="B");\n}\n\ncl {\n    async def app() -> Any {\n        a = await getItem1();\n        b = await getItem2();\n        return <div>{a.name} {b.name}</div>;\n    }\n}\n';
    mod = compile_inline(code, prog);
    js = mod.gen.js;

    # Should only have one class declaration, not duplicates
    assert js.count("class Item") == 1 , "Shared type should only be emitted once even when multiple functions return it";
    assert js.count('__jacRegisterType("Item"') == 1 , "Registration should only happen once";
}
