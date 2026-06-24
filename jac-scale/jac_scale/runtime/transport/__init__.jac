"""Service transport: how an `sv` call reaches its target service.

The `ServiceTransport` port has two adapters. `InProcessTransport` dispatches to
a locally-registered callable with no network hop - this is how a monolith
collapses the microservice blueprint to N=1. `HttpTransport` (re-homed with the
rpc layer) forwards over the network for distributed topologies. The gateway and
rpc layer call the port, never a concrete transport, so they never branch on
topology.
"""
