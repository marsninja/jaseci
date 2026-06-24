"""Shared-state port for jac-scale cross-cutting features.

Rate limiting, scheduler leader-election, and the one-time token store all read
and write through the `StateBackend` port rather than touching a concrete store
directly. The `--scale` dial selects the adapter: `InProcessStateBackend` (the
zero-dependency default for local monolith and local microservice) or a
`RedisStateBackend` (multi-replica k8s, provided by jac-storage). Routing every
consumer through one port is the seam that keeps behavior identical from a local
monolith up to a distributed fleet.
"""
