"""Bug #EXCEPT-UNRESOLVED: except-clause binding from an unresolved exception class.

The optional-dependency shim pattern below guards a third-party import and, on
ImportError, falls back to `ApiException = Exception`. The type checker sees the
fallback and resolves `ApiException` to the guessed supertype Exception, so
`except ApiException as e` bound `e` as an Exception instance and every domain
attribute access (e.status, e.reason) hard-errored E1030 -- 92+ such instances
across the in-repo jac-scale kubernetes deploy targets.

`ApiException` here is not a real class declaration (it is a bare Name reassigned
to a stand-in), so the handler variable must degrade to Any -- permissive
attribute access, no fabricated errors.
"""

with entry {
    try {
        import from optional_dep_absent.client.rest { ApiException }
    } except ImportError {
        ApiException = Exception;
    }
}


def check_secret -> bool {
    try {
        return True;
    } except ApiException as e {
        if e.status == 404 {
            return False;
        }
        if e.reason.upper().startswith("N") {
            return False;
        }
        raise;
    }
}
