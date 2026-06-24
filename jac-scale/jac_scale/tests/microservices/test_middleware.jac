"""Tests for the Middleware port and the composing registry."""

import asyncio;
import from jac_scale.runtime.middleware.middleware { Middleware, MiddlewareRegistry }


"""Records enter/exit around call_next so onion ordering is observable."""
obj RecordingMiddleware(Middleware) {
    has recorder: list[str] = [];

    async def handle(request: any, call_next: any) -> any {
        self.recorder.append(f"enter:{self.name}");
        result = await call_next(request);
        self.recorder.append(f"exit:{self.name}");
        return result;
    }
}


"""Returns a fixed response without calling call_next (short-circuit)."""
obj ShortCircuitMiddleware(Middleware) {
    has response: str = "blocked";

    async def handle(request: any, call_next: any) -> any {
        return self.response;
    }
}


async def _handler(request: any) -> any {
    return "handler";
}


test "an empty registry calls the handler directly" {
    registry = MiddlewareRegistry();
    assert asyncio.run(registry.run("req", _handler)) == "handler";
}


test "registering is one call and ordering is by ascending priority" {
    registry = MiddlewareRegistry();
    registry.register(Middleware(name="z", priority=30));
    registry.register(Middleware(name="x", priority=10));
    registry.register(Middleware(name="y", priority=20));
    names = [item.name for item in registry.middlewares];
    assert names == ["x", "y", "z"];
}


test "middlewares wrap the handler in onion order (lowest priority outermost)" {
    registry = MiddlewareRegistry();
    log: list[str] = [];
    registry.register(RecordingMiddleware(name="b", priority=20, recorder=log));
    registry.register(RecordingMiddleware(name="a", priority=10, recorder=log));
    result = asyncio.run(registry.run("req", _handler));
    assert result == "handler";
    assert log == ["enter:a", "enter:b", "exit:b", "exit:a"];
}


test "a middleware can short-circuit without running inner middleware or handler" {
    registry = MiddlewareRegistry();
    log: list[str] = [];
    registry.register(ShortCircuitMiddleware(name="gate", priority=5));
    registry.register(RecordingMiddleware(name="inner", priority=10, recorder=log));
    result = asyncio.run(registry.run("req", _handler));
    assert result == "blocked";
    assert log == [];
}
