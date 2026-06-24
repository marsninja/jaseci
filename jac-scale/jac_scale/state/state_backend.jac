"""StateBackend port and its zero-dependency in-process default.

The port exposes the minimum primitives the cross-cutting features need:
key/value storage with TTL, an atomic float counter (token-bucket style rate
limiting), and an expiring mutual-exclusion lock (scheduler leader election).
A Redis-backed adapter implements the same port for multi-replica deployments
so that state does not fragment across pods.
"""

import time;
import from threading { Lock as _StateLock }

"""Module-wide guard for the in-process backend. Contention is negligible: every
critical section is a dict read-modify-write over tiny values."""
glob _state_lock = _StateLock();


"""Abstract shared-state contract.

Implementations must be safe to call concurrently. All TTLs are in seconds; a
None TTL means the entry never expires. String values keep the port trivially
serializable across both in-process and network adapters.
"""
obj StateBackend {
    """Return the stored value for `key`, or None if it is absent or expired."""
    def get(key: str) -> (str | None) {
        raise NotImplementedError("get() must be implemented by a StateBackend");
    }

    """Store `value` under `key`, expiring after `ttl_seconds` when provided."""
    def set(key: str, value: str, ttl_seconds: (int | None) = None) -> None {
        raise NotImplementedError("set() must be implemented by a StateBackend");
    }

    """Remove `key` if present; a no-op when it is already absent."""
    def delete(key: str) -> None {
        raise NotImplementedError("delete() must be implemented by a StateBackend");
    }

    """Atomically add `amount` to the float counter at `key` and return the new
    total. Creates the counter at 0.0 when absent; `ttl_seconds` sets the expiry
    only on first creation."""
    def increment(key: str, amount: float = 1.0, ttl_seconds: (int | None) = None) -> float {
        raise NotImplementedError("increment() must be implemented by a StateBackend");
    }

    """Try to acquire the mutually-exclusive lock `key`, auto-expiring after
    `ttl_seconds`. Returns True on success. Used for scheduler leader election so
    a job fires exactly once across replicas."""
    def acquire_lock(key: str, ttl_seconds: int) -> bool {
        raise NotImplementedError("acquire_lock() must be implemented by a StateBackend");
    }

    """Release a lock previously taken with acquire_lock(); a no-op if not held."""
    def release_lock(key: str) -> None {
        raise NotImplementedError("release_lock() must be implemented by a StateBackend");
    }
}


"""Process-local StateBackend backed by a dict guarded by the module lock.

Single-process only: it is the default when `--scale` is absent (local monolith
or local microservice dev). State does NOT span replicas, which is the correct
behavior for those cells; multi-replica k8s selects RedisStateBackend instead.
"""
obj InProcessStateBackend(StateBackend) {
    # key -> (value, expiry_epoch); expiry_epoch 0.0 means "never expires".
    has _values: dict[str, tuple[str, float]] = {};
    # lock name -> expiry_epoch
    has _locks: dict[str, float] = {};

    """Drop `key` if it has passed its expiry. Caller must hold _state_lock."""
    def _purge_if_expired(key: str, now: float) -> None {
        entry = self._values.get(key);
        if entry is not None {
            (_, expiry) = entry;
            if expiry != 0.0 and now >= expiry {
                self._values.pop(key, None);
            }
        }
    }

    def get(key: str) -> (str | None) {
        now = time.time();
        with _state_lock {
            self._purge_if_expired(key, now);
            entry = self._values.get(key);
            if entry is None {
                return None;
            }
            (value, _) = entry;
            return value;
        }
    }

    def set(key: str, value: str, ttl_seconds: (int | None) = None) -> None {
        expiry = (time.time() + ttl_seconds) if ttl_seconds is not None else 0.0;
        with _state_lock {
            self._values[key] = (value, expiry);
        }
    }

    def delete(key: str) -> None {
        with _state_lock {
            self._values.pop(key, None);
        }
    }

    def increment(key: str, amount: float = 1.0, ttl_seconds: (int | None) = None) -> float {
        now = time.time();
        with _state_lock {
            self._purge_if_expired(key, now);
            entry = self._values.get(key);
            if entry is not None {
                (raw, keep_expiry) = entry;
                current = float(raw);
            } else {
                current = 0.0;
                keep_expiry = (now + ttl_seconds) if ttl_seconds is not None else 0.0;
            }
            updated = current + amount;
            self._values[key] = (str(updated), keep_expiry);
            return updated;
        }
    }

    def acquire_lock(key: str, ttl_seconds: int) -> bool {
        now = time.time();
        with _state_lock {
            held_until = self._locks.get(key);
            if held_until is not None and now < held_until {
                return False;
            }
            self._locks[key] = now + ttl_seconds;
            return True;
        }
    }

    def release_lock(key: str) -> None {
        with _state_lock {
            self._locks.pop(key, None);
        }
    }
}
