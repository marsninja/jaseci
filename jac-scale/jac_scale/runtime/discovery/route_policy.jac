"""Route-prefix policy: one place that turns a service module name into its
gateway prefix.

This is the single source of truth consumed by the backend router (longest-prefix
match), the frontend `serviceRoutes` map injected into the SPA, and OpenAPI
path-prefixing - so the path scheme is identical on every side.

No `/api/` prefix: a service module `orders_app` is served at `/orders`. Dropping
that prefix removes the namespace that previously kept service routes clear of
builtin gateway segments, so a reserved-name guard rejects, at discovery time,
any service whose route would shadow a builtin (walker, function, admin, ...).
"""

"""Builtin gateway path segments a service route must never shadow."""
glob _RESERVED_SEGMENTS: set[str] = {
         "api",
         "walker",
         "function",
         "user",
         "sso",
         "api-key",
         "webhook",
         "ws",
         "jobs",
         "graph",
         "admin",
         "static",
         "health",
         "healthz",
         "metrics",
         "openapi.json",
         "docs"
     };


"""The route slug for a module name, stripping the conventional `_app` suffix
(`orders_app` -> `orders`)."""
def service_slug(module_name: str) -> str {
    name = module_name;
    if name.endswith("_app") {
        name = name[:-4];
    }
    return name;
}


"""The gateway route prefix for a service module: `/<slug>`, no `/api/`."""
def derive_route_prefix(module_name: str) -> str {
    return f"/{service_slug(module_name)}";
}


"""True when a module's route slug collides with a builtin gateway segment."""
def is_reserved(module_name: str) -> bool {
    return service_slug(module_name) in _RESERVED_SEGMENTS;
}


"""Raise ValueError when a service route would shadow a builtin gateway segment.

Called at discovery time so the collision surfaces with an actionable message
instead of silently shadowing a builtin path once the gateway is serving.
"""
def guard_route_name(module_name: str) -> None {
    if is_reserved(module_name) {
        slug = service_slug(module_name);
        raise ValueError(
            f"service '{module_name}' derives the route '/{slug}', which collides "
            + f"with a builtin gateway segment. Rename the service module so its "
            + f"route does not shadow a builtin path."
        );
    }
}
