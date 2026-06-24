"""Service discovery and route policy for the jac-scale runtime.

Discovery finds services from the `sv import` closure; the route policy derives
each service's gateway prefix. The route policy is the single source of truth
shared by the backend router, the frontend `serviceRoutes` injection, and
OpenAPI path-prefixing, so the path scheme is uniform everywhere by construction.
"""
