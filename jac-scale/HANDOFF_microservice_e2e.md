# Handoff - jac-scale rearchitecture + k8s_e2e microservice e2e

Branch: `feat/jac-scale-rearchitecture` (PR #6937, base jaseci-labs/jaseci `main`, fork origin `git@github.com:MusabMahmoodh/jaseci.git`)
Last updated: 2026-06-26

## TL;DR - where we are

The full local **microservice** path now works end-to-end against the
`jac-scale/jac_scale/tests/fixtures/k8s_e2e` fixture (Jac Shop): login ->
authed function calls across services (`/products/function/list_products`,
`/cart/function/view_cart`, `/orders/...`) all 200. The two bugs that
blocked it are fixed (below).

**Next task: actually deploy + test on microk8s with `--scale`** (see
"Next session" at the bottom).

## Bugs fixed this session

### 1. `[object Object]` in the signup/login form (ROOT CAUSE)

The fixture's client components returned `-> any`, so the jaclang client
compiler treated them as **plain functions, not React components** -> props
were never destructured (first param received the whole props object,
the rest got `{}`). littleX's components return `-> JsxElement`, which is
what triggers the props-destructuring codegen.

Fix: changed the return type on both components:

- `tests/fixtures/k8s_e2e/components/AuthForm.cl.jac`  `-> any` -> `-> JsxElement`
- `tests/fixtures/k8s_e2e/components/Button.cl.jac`    `-> any` -> `-> JsxElement`

Rule of thumb: **a `.cl.jac` function that returns JSX must be typed
`-> JsxElement`**, never `-> any`. Worth a lint/compiler warning later.

### 2. `[object Object]` rendered from the signup error envelope

The client runtime handed the raw `{code, message, details}` error object
straight to the UI. Added a `__errorMessage()` unwrap helper in the
jaclang client runtime (mirrors how the success path unwraps `data`):

- `jac/jaclang/runtimelib/impl/client_runtime_core.impl.jac` (+ `.cl.jac` decl)
- Used in `__doFuncFetch` and `jacSignup`.

NOTE: this touches **jaclang core** (normally off-limits per the
hookspec rule). It's a genuine client-runtime correctness fix, but flag it
in PR review / consider whether it belongs in core or should be unwrapped
app-side. The fixture also has a defensive app-side unwrap in
`frontend.impl.jac handleSignup` (commit cde143b8c) which is now redundant
with the core fix - decide whether to keep one or both.

## Auth-across-services: how it actually works (verified, NOT broken)

The 401s seen mid-session were a stale run; the architecture is sound:

- `/user/login` is a **passthrough** segment (`runtime/gateway/dispatch.jac:33`,
  `runtime/discovery/route_policy.jac:19`) - forwarded to a backend service,
  which signs the JWT.
- `/products/function/...` is a **service-prefixed** route (ROUTE_SERVICE),
  proxied to the owning service; `build_forward_headers`
  (`runtime/gateway/microservice_gateway.impl.jac:344`) forwards `Authorization`
  (only host/transfer-encoding/connection/keep-alive are stripped as hop-by-hop).
- `validate_jwt_token` (`identity/impl/user_manager.impl.jac:243`) is
  **decode-only** (no per-service user-store lookup), so a token signed by
  one process validates in another **as long as `JWT_SECRET` matches**.
- `JWT_SECRET` comes from `[plugins.scale.jwt].secret` and defaults to the
  fixed `'supersecretkey_for_testing_only!'` (`config/impl/config_loader.impl.jac:168`),
  so every local process shares it. For real deploys, set a real secret
  (and in K8s it must be the **same** secret in every pod - shared via the
  injected env/secret).

If 401s ever come back, check in this order: service-side log
`.jac/logs/<svc>.log` for `Failed to validate JWT token` (it's `logger.debug`,
so raise log level to see it); confirm the `Authorization` header reaches the
service; confirm all processes resolve the same `JWT_SECRET`.

## Uncommitted working tree (as of handoff)

```
M jac-scale/jac_scale/admin/ui/jac.toml                         # @tanstack/react-form re-added by build tooling
M jac-scale/jac_scale/tests/fixtures/k8s_e2e/components/AuthForm.cl.jac   # JsxElement fix + debug probe stripped
M jac-scale/jac_scale/tests/fixtures/k8s_e2e/components/Button.cl.jac     # JsxElement fix
M jac-scale/jac_scale/tests/fixtures/k8s_e2e/frontend.cl.jac    # authUsername/authPassword state rename
M jac-scale/jac_scale/tests/fixtures/k8s_e2e/frontend.impl.jac  # rename + defensive signup unwrap
M jac-scale/jac_scale/tests/fixtures/k8s_e2e/jac.toml           # react-form add; CHECK: [plugins.scale.microservices] block was removed - confirm intended
M jac/examples/littleX/jac.toml                                 # react-form re-add (build tooling)
M jac/jaclang/runtimelib/client_runtime_core.cl.jac            # __errorMessage decl (CORE)
M jac/jaclang/runtimelib/impl/client_runtime_core.impl.jac     # __errorMessage impl (CORE)
```

TODO before committing:

1. Verify the `[plugins.scale.microservices]` removal in `k8s_e2e/jac.toml`
   is intentional (auto-discovery from `sv import`) and not an accidental
   revert. If services still come up + route, it's fine.
2. Decide keep/revert the core `__errorMessage` change vs the app-side
   `handleSignup` unwrap (don't keep redundant belt-and-suspenders without
   a reason).
3. Suggested commit split:
   - `fix(client): type JSX-returning .cl.jac components as JsxElement` (AuthForm/Button)
   - `fix(jaclang-client): unwrap error envelope message, never render [object Object]` (core)
   - fixture state-rename + jac.toml as a fixture-cleanup commit.

## Reproduce the local microservice run

```
cd jac-scale/jac_scale/tests/fixtures/k8s_e2e
rm -rf .jac/client/dist .jac/client/compiled    # force fresh client build
jac build main.jac
jac start                                         # gateway :8000 + per-service subprocs
```

Service logs: `.jac/logs/{products_app,cart_app,orders_app}.log`.
PIDs: `.jac/run/*.pid`. Gateway proxy lines tag `Proxy: POST /<svc>/... -> 127.0.0.1:<port>/...`.

Environment gotchas (from earlier):

- Use the editable jac-scale in the jac binary's runtime, not the PyPI copy.
  Confirm with `jac -c '...'` that it LOADS the repo path, not
  `~/.cache/jac/rt/<hash>/.../site-packages/jac_scale`. If shadowed:
  `rm -rf` that copy + `jac install -e ./jac-scale --extras deploy --global`.
- `JAC_NO_DEV_SOURCE=1 jac start` uses bundled jaclang (avoids recompiling
  dev jaclang / the LLVM `mapLevel` panic). Do NOT `rm -rf ~/.cache/jac/rt`.

## Next session: microk8s `--scale` deploy

Goal: deploy the same fixture to microk8s and confirm authed cross-service
calls work in-cluster (where each service is a real pod and the shared
state backend is provisioned).

### Pre-deploy: storage (the real PVC blocker - CORRECTED)

The PVC-binding issue is **mongo, not redis**. Verified against the manifests:

- `deploy/database/kubernetes_mongo.jac:117` mongo is a StatefulSet with a
  `volumeClaimTemplates` (`ReadWriteOnce`, `requests.storage`) and **no
  `storageClassName`** -> it binds to the cluster's DEFAULT StorageClass.
- `deploy/database/kubernetes_redis.jac` redis is a Deployment with **only
  `emptyDir`** (ephemeral L2 cache, `save ""`, `appendonly no`) - it has NO
  PVC, so it can never be blocked on storage. Any redis restarts seen earlier
  were a side effect of the broken run, not a storage problem.

A fresh MicroK8s has **no default StorageClass**, so the mongo PVC stays
`Pending` forever and mongo never starts. Enable it BEFORE deploying:

```
microk8s enable hostpath-storage          # creates + defaults microk8s-hostpath SC
microk8s enable dns ingress               # gateway Ingress (host jac-shop.local) needs ingress
kubectl get storageclass                  # confirm one is marked (default)
```

Leaving `storageClassName` unset is intentional and portable (EKS/GKE/AKS
supply their own default SC); do NOT hardcode `microk8s-hostpath` into the
manifest.

Diagnose if a DB pod is stuck after deploy:

```
kubectl get pods,pvc
kubectl describe pvc <name>               # "no persistent volumes available / no default SC" -> enable hostpath-storage
kubectl describe pod -l component=database
kubectl logs <mongo-pod>
```

Deploy command path: `jac start --scale` -> `KubernetesRealizer.realize`
(wrapped in try/except in `plugin.jac` so failures abort with rc=1 instead
of silently falling back to local serve). `--experimental` bootstrap path
is preserved.

Things to verify in-cluster:

- All service pods + gateway Ready; redis/mongo StatefulSets healthy.
- `JWT_SECRET` injected identically into every pod (env/secret) so tokens
  validate across pods.
- Shared state backend (Mongo/Redis) actually used (not per-pod sqlite).
- Static SPA served via the gateway (`serve_project_static`, candidate dirs
  assets/ dist/ public/ .jac/client/{dist,compiled}).
