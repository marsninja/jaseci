"""The jac-scale serving runtime.

Holds the topology-agnostic request machinery: service transport, routing,
gateway, middleware, discovery, lifecycle, and context propagation. The runtime
depends only on ports; the realizer wires concrete adapters from the deployment
dials so the same blueprint serves a local monolith or a k8s microservice fleet.
"""
