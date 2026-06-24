"""Selects and caches the process-wide StateBackend from the deployment dial.

`--scale` (multi-replica k8s) will select a RedisStateBackend so shared state
spans pods; every other cell uses the in-process default. Centralizing the
choice here keeps every consumer (rate limiting, scheduler locks, token store)
agnostic to which backend is wired.

Until the Redis adapter lands in jac-storage both paths return the in-process
backend, so this commit changes no behavior. The Redis branch is added with that
adapter.
"""

import from jac_scale.state.state_backend { StateBackend, InProcessStateBackend }

"""Single-slot holder so the backend is created once per process. A dict avoids
reassigning a module global from inside the function."""
glob _backend_holder: dict[str, StateBackend] = {};


"""Return the process-wide StateBackend, creating it on first use.

Args:
    scale_enabled: reflects the --scale dial. Reserved for selecting the Redis
        adapter; today both paths use the in-process backend.
"""
def get_state_backend(scale_enabled: bool = False) -> StateBackend {
    backend = _backend_holder.get("default");
    if backend is None {
        backend = InProcessStateBackend();
        _backend_holder["default"] = backend;
    }
    return backend;
}


"""Reset the cached backend. Test helper; not used in production paths."""
def reset_state_backend() -> None {
    _backend_holder.clear();
}
