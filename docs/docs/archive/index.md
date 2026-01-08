# Archived Documentation

This section contains documentation for deprecated features and legacy systems. Content here is preserved for reference but should not be used for new projects.

## Archived Content

### [jac-cloud (Deprecated)](jac-cloud/introduction.md)

!!! warning "Deprecated"
    jac-cloud has been replaced by [jac-scale](../production/index.md). Use jac-scale for all new projects.

jac-cloud was the original cloud deployment system for Jac. It has been superseded by jac-scale, which provides:

- Improved Kubernetes integration
- Better memory management (L1/L2/L3 tiers)
- Enhanced scalability features
- Simplified configuration

**jac-cloud Topics (for reference only):**

- [Introduction](jac-cloud/introduction.md)
- [Quickstart](jac-cloud/quickstart.md)
- [Permissions](jac-cloud/permission.md)
- [Logging](jac-cloud/logging.md)
- [Environment Variables](jac-cloud/env_vars.md)
- [SSO Implementation](jac-cloud/sso_implementation.md)
- [WebSocket](jac-cloud/websocket.md)
- [Scheduler](jac-cloud/scheduler.md)
- [Async Walker](jac-cloud/async_walker.md)
- [Webhook](jac-cloud/webhook.md)
- [Deployment](jac-cloud/deployment.md)
- [Utilities](jac-cloud/utilities.md)

## Migration Guides

If you're migrating from deprecated features:

1. **jac-cloud to jac-scale**: Replace `jac serve` usage with jac-scale's `jac serve` and `jac scale` commands. See the [jac-scale documentation](../production/index.md).
