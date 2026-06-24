"""Code-injection port for jac-scale k8s deploys.

An Injector decides how a service's source reaches its pod. The default
`ObjectStoreInjector` packs the project, stores it in an in-cluster object store
(MinIO), and has an init container fetch and unpack it before the app starts.
This needs no Docker daemon and no external registry, and is not bounded by the
1 MiB etcd ConfigMap limit. An `ImageInjector` (built in a later, deferred PR)
slots in behind the same port for image-based deploys.
"""
