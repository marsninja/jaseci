"""Realizers: turn a RealizationPlan into a running system.

The pre-hook does not branch on topology or environment itself; it hands control
to a Realizer, which consults the RealizationPlanner and dispatches to the serving
strategy the plan selects. LocalRealizer serves on the developer's machine
(monolith in-process, or a real-process microservice fleet); the kubernetes
realizer deploys. Keeping the branching in one component is the DIP seam that lets
the unified flow stay one path.
"""
