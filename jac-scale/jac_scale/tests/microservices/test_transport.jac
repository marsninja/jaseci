"""Tests for the ServiceTransport port and the in-process collapse adapter."""

import from jac_scale.runtime.transport.transport { InProcessTransport }


test "a registered function is dispatched in-process and returns its result" {
    transport = InProcessTransport();
    transport.register_function("orders", "create", lambda payload: dict : payload["qty"] * 2);
    assert transport.call_function("orders", "create", {"qty": 3}) == 6;
}


test "a registered walker is dispatched in-process and returns its result" {
    transport = InProcessTransport();
    transport.register_walker("cart", "Checkout", lambda payload: dict : {"ok": True, "items": payload["items"]});
    result = transport.call_walker("cart", "Checkout", {"items": 2});
    assert result == {"ok": True, "items": 2};
}


test "functions and walkers keep separate namespaces" {
    transport = InProcessTransport();
    transport.register_function("svc", "shared", lambda payload: dict : "function");
    transport.register_walker("svc", "shared", lambda payload: dict : "walker");
    assert transport.call_function("svc", "shared", {}) == "function";
    assert transport.call_walker("svc", "shared", {}) == "walker";
}


test "calling an unregistered function raises a clear error" {
    transport = InProcessTransport();
    failed = False;
    try {
        transport.call_function("orders", "missing", {});
    } except KeyError as err {
        failed = True;
        assert "orders:missing" in str(err);
    }
    assert failed;
}
