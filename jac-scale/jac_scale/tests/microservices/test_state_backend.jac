"""Tests for the StateBackend port and its in-process default."""

import time;
import from jac_scale.state.state_backend { InProcessStateBackend }
import from jac_scale.state.factory { get_state_backend, reset_state_backend }


test "set then get returns the stored value" {
    backend = InProcessStateBackend();
    backend.set("greeting", "hello");
    assert backend.get("greeting") == "hello";
}


test "get returns None for a missing key" {
    backend = InProcessStateBackend();
    assert backend.get("absent") is None;
}


test "delete removes a stored value" {
    backend = InProcessStateBackend();
    backend.set("temp", "value");
    backend.delete("temp");
    assert backend.get("temp") is None;
}


test "values without a ttl never expire" {
    backend = InProcessStateBackend();
    backend.set("durable", "value");
    time.sleep(0.02);
    assert backend.get("durable") == "value";
}


test "a value past its ttl is dropped on read" {
    backend = InProcessStateBackend();
    backend.set("ephemeral", "value", ttl_seconds=0);
    time.sleep(0.02);
    assert backend.get("ephemeral") is None;
}


test "increment accumulates atomically and returns the new total" {
    backend = InProcessStateBackend();
    assert backend.increment("counter", 1.0) == 1.0;
    assert backend.increment("counter", 2.5) == 3.5;
}


test "acquire_lock is exclusive until released" {
    backend = InProcessStateBackend();
    assert backend.acquire_lock("job", 60);
    assert not backend.acquire_lock("job", 60);
    backend.release_lock("job");
    assert backend.acquire_lock("job", 60);
}


test "the factory returns a process-wide singleton" {
    reset_state_backend();
    first = get_state_backend(False);
    second = get_state_backend(False);
    assert first is second;
}
