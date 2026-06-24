"""Tests for the route-prefix policy (no /api/, reserved-name guard)."""

import from jac_scale.runtime.discovery.route_policy {
    service_slug,
    derive_route_prefix,
    is_reserved,
    guard_route_name
}


test "the _app suffix is stripped from the slug" {
    assert service_slug("orders_app") == "orders";
    assert service_slug("cart") == "cart";
}


test "the route prefix has no /api/ segment" {
    assert derive_route_prefix("orders_app") == "/orders";
    assert derive_route_prefix("jac_coder_sv") == "/jac_coder_sv";
}


test "names that collide with builtin segments are reserved" {
    assert is_reserved("admin_app");
    assert is_reserved("static");
    assert is_reserved("metrics");
    assert not is_reserved("orders_app");
}


test "the guard raises for a reserved route and is silent otherwise" {
    guard_route_name("orders_app");
    failed = False;
    try {
        guard_route_name("admin_app");
    } except ValueError as err {
        failed = True;
        assert "/admin" in str(err);
    }
    assert failed;
}
