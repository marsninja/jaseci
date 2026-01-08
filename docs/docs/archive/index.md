# Archived Documentation

This section contains documentation for deprecated features and legacy systems.

## jac-cloud (Deprecated)

!!! warning "jac-cloud has been removed"
    jac-cloud documentation has been archived. For production deployments, use **jac-scale**.

    See the [Production (jac-scale) documentation](../production/index.md) for:

    - REST API generation from walkers
    - Kubernetes deployment with `jac scale`
    - Three-tier memory architecture (L1/L2/L3)
    - Authentication and SSO
    - Health checks and scaling

## Migration Guide

If you're migrating from jac-cloud to jac-scale:

| jac-cloud | jac-scale |
|-----------|-----------|
| `pip install jac-cloud` | `pip install jac-scale` |
| `jac serve app.jac` | `jac serve app.jac` (same) |
| Manual K8s setup | `jac scale app.jac` (auto) |
| MongoDB config | Auto-provisioned |
| Redis config | Auto-provisioned |

For detailed migration instructions, see [Production Deployment](../production/index.md).
