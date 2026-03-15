"""Tests for shared type serialization in server responses.

Validates that server endpoints return _jac_type metadata for archetype objects,
enabling client-side auto-deserialization into typed instances.
"""

import json;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from jaclang.runtimelib.testing { JacTestClient }

glob FIXTURES = str(Path(__file__).parent / "fixtures");

def fixture_abs_path(filename: str) -> str {
    return str((Path(FIXTURES) / filename).resolve());
}

# =============================================================================
# Server-side serialization: _jac_type metadata in responses
# =============================================================================
test "function returning archetype includes _jac_type metadata" {
    with TemporaryDirectory() as tmpdir {
        client = JacTestClient.from_file(
            fixture_abs_path("serve_shared_types.jac"), base_path=tmpdir
        );
        client.register_user("shared_user1", "pass123");
        resp = client.post("/function/get_user", json={"id": "123"});
        assert resp.ok , f"get_user request failed: {resp.data}";
        result = resp.data.get("result", {});
        assert result.get("name") == "Alice" , "Should return correct name field";
        assert result.get("age") == 30 , "Should return correct age field";
        assert result.get("_jac_type") == "UserProfile" , "Server should annotate response with _jac_type for archetype returns";
        assert "_jac_id" in result , "Server should include _jac_id for archetype objects";
        client.close();
    }
}

test "nested archetype returns include _jac_type at all levels" {
    with TemporaryDirectory() as tmpdir {
        client = JacTestClient.from_file(
            fixture_abs_path("serve_shared_types.jac"), base_path=tmpdir
        );
        client.register_user("shared_user2", "pass123");
        resp = client.post("/function/get_full_user", json={});
        assert resp.ok , f"get_full_user request failed: {resp.data}";
        result = resp.data.get("result", {});
        # Top-level type
        assert result.get("_jac_type") == "FullUser" , "Top-level should have _jac_type=FullUser";
        # Nested profile
        profile = result.get("profile", {});
        assert profile.get("_jac_type") == "UserProfile" , "Nested profile should have _jac_type=UserProfile";
        assert profile.get("name") == "Bob";
        assert profile.get("age") == 25;
        # Nested address
        address = result.get("address", {});
        assert address.get("_jac_type") == "Address" , "Nested address should have _jac_type=Address";
        assert address.get("street") == "123 Main St";
        assert address.get("city") == "NYC";
        client.close();
    }
}

test "walker reports include _jac_type for archetype objects" {
    with TemporaryDirectory() as tmpdir {
        client = JacTestClient.from_file(
            fixture_abs_path("serve_shared_types.jac"), base_path=tmpdir
        );
        client.register_user("shared_user3", "pass123");
        resp = client.post("/walker/FetchUser", json={});
        assert resp.ok , f"FetchUser request failed: {resp.data}";
        reports = resp.data.get("reports", []);
        assert len(reports) > 0 , "Walker should have reported something";
        reported = reports[0];
        assert reported.get("name") == "Charlie" , "Reported object should have correct name";
        assert reported.get("age") == 40 , "Reported object should have correct age";
        assert reported.get("_jac_type") == "UserProfile" , "Walker reports should include _jac_type metadata for archetypes";
        client.close();
    }
}

test "function returning dict does NOT include _jac_type" {
    with TemporaryDirectory() as tmpdir {
        client = JacTestClient.from_file(
            fixture_abs_path("serve_shared_types.jac"), base_path=tmpdir
        );
        client.register_user("shared_user4", "pass123");
        resp = client.post("/function/get_data", json={});
        assert resp.ok , f"get_data request failed: {resp.data}";
        result = resp.data.get("result", {});
        assert result.get("key") == "value";
        assert result.get("count") == 42;
        # Plain dicts should NOT have _jac_type
        assert "_jac_type" not in result , "Plain dict returns should not have _jac_type metadata";
        client.close();
    }
}

# =============================================================================
# Client codegen: shared types in generated JS from fixture
# =============================================================================
test "shared type classes appear in compiled JS output" {
    import from jaclang.jac0core.program { JacProgram }
    prog = JacProgram();
    mod = prog.compile(fixture_abs_path("serve_shared_types.jac"));
    js = mod.gen.js;

    # Shared archetype classes should be emitted to JS
    assert "class UserProfile" in js , "UserProfile should be emitted as JS class";
    assert "class Address" in js , "Address should be emitted as JS class";
    assert "class FullUser" in js , "FullUser (with nested types) should be emitted as JS class";

    # Registration calls
    assert '__jacRegisterType("UserProfile", UserProfile)' in js , "UserProfile should be registered in type registry";
    assert '__jacRegisterType("Address", Address)' in js , "Address should be registered";
    assert '__jacRegisterType("FullUser", FullUser)' in js , "FullUser should be registered";

    # Runtime import
    assert "__jacRegisterType" in js;
    assert '@jac/runtime' in js;
}

test "shared type manifest is populated from fixture" {
    import from jaclang.jac0core.program { JacProgram }
    prog = JacProgram();
    mod = prog.compile(fixture_abs_path("serve_shared_types.jac"));
    manifest = mod.gen.client_manifest;

    assert "UserProfile" in manifest.shared_types;
    assert "Address" in manifest.shared_types;
    assert "FullUser" in manifest.shared_types;

    # Validate field info for UserProfile
    up = manifest.shared_types["UserProfile"];
    field_names = [f[0] for f in up.fields];
    assert "name" in field_names;
    assert "age" in field_names;

    # Validate field info for Address
    addr = manifest.shared_types["Address"];
    addr_fields = [f[0] for f in addr.fields];
    assert "street" in addr_fields;
    assert "city" in addr_fields;
}
