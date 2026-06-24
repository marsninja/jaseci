"""ServiceTransport port and the in-process (monolith-collapse) adapter.

A transport invokes a function or spawns a walker on a named service and returns
the result. The blueprint always declares service boundaries; the transport
decides whether crossing one is a direct call (monolith) or a network hop
(microservice). Keeping that decision behind the port is what makes
"works local => works cloud" structural rather than aspirational.
"""


"""Abstract transport contract. `payload` is the already-marshalled call data;
the return value is the target's result. Adapters must be safe to share across
concurrent requests."""
obj ServiceTransport {
    """Invoke function `name` on `service` with `payload` and return its result."""
    def call_function(service: str, name: str, payload: dict[str, any]) -> any {
        raise NotImplementedError("call_function() must be implemented by a ServiceTransport");
    }

    """Spawn walker `name` on `service` with `payload` and return its result."""
    def call_walker(service: str, name: str, payload: dict[str, any]) -> any {
        raise NotImplementedError("call_walker() must be implemented by a ServiceTransport");
    }
}


"""Compose the registry key for a service member so functions and walkers in the
same service share one namespace per kind."""
def _member_key(service: str, name: str) -> str {
    return f"{service}:{name}";
}


"""In-process transport: dispatches an `sv` call to a locally-registered
callable with no network hop.

This is the collapse that turns the microservice blueprint into a monolith: the
realizer registers every service's functions and walkers here, and a cross-service
call becomes a direct invocation. Because the boundary is still declared (the
call still goes through the transport), expanding to HttpTransport later changes
only the wire, never the app code.
"""
obj InProcessTransport(ServiceTransport) {
    has _functions: dict[str, any] = {};
    has _walkers: dict[str, any] = {};

    """Register the local callable backing function `name` on `service`."""
    def register_function(service: str, name: str, handler: any) -> None {
        self._functions[_member_key(service, name)] = handler;
    }

    """Register the local callable backing walker `name` on `service`."""
    def register_walker(service: str, name: str, handler: any) -> None {
        self._walkers[_member_key(service, name)] = handler;
    }

    def call_function(service: str, name: str, payload: dict[str, any]) -> any {
        key = _member_key(service, name);
        handler = self._functions.get(key);
        if handler is None {
            raise KeyError(f"no in-process function registered for {key}");
        }
        return handler(payload);
    }

    def call_walker(service: str, name: str, payload: dict[str, any]) -> any {
        key = _member_key(service, name);
        handler = self._walkers.get(key);
        if handler is None {
            raise KeyError(f"no in-process walker registered for {key}");
        }
        return handler(payload);
    }
}
