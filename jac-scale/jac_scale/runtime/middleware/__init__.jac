"""Composable gateway middleware.

A middleware is one cross-cutting concern (rate limiting, draining, metrics, auth
context, tracing). Adding one is meant to be trivial: subclass `Middleware`,
implement `handle`, and `register` it. The same registry feeds both the embedded
and the process gateway, so a middleware is written once and runs in every
topology.
"""
