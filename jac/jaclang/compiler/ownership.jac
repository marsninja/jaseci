"""Result-ownership classification (One Owner Per Analysis, Phase 7).

THE written reference-counting ownership invariant for Jac expression
results. Backends consume this classification instead of deciding
per emission site which values carry a reference; the rules below are
the single home of the answer to "does this expression's result arrive
with a +1 the consumer must balance?".

Classification:

- OWNED: the expression's pointer-typed result carries a +1 reference
  that its consumer must release, store, or hand on. Every
  pointer-returning call is OWNED (user functions RETAIN internally for
  borrowed refs or donate a named local's ref via the return path's
  skip-var mechanism; foreign scalar-pointer returns are treated as
  transferred until Phase 8 attaches declared borrow/move attributes to
  the foreign boundary). Fresh aggregate literals (list/set/dict),
  comprehensions, and fresh string buffers (f-strings, multi-part
  multistrings) are OWNED.

- BORROWED: reads through an existing owner - names and attribute /
  index loads. The owner (local, field, container) holds the reference;
  the reader must retain before storing the value anywhere that
  outlives the owner.

- STATIC: immortal literals (string constants and single-part
  multistrings); never retained or released.

- UNKNOWN: forms whose result ownership is decided by backend emission
  mechanics rather than expression shape (operator results, coercion /
  boxing temporaries the emitter materializes). Backends own the
  bookkeeping for these, driven by the classification of their source
  expressions.
"""
import jaclang.jac0core.unitree as uni;
import from enum { Enum }

enum Ownership {
    OWNED = "owned",
    BORROWED = "borrowed",
    STATIC = "static",
    UNKNOWN = "unknown"
}

"""Classify an expression's result ownership (see module docstring).

Pure function of expression shape: SetCompr/GenCompr are covered by the
ListCompr arm through inheritance.
"""
def result_ownership(expr: (uni.Expr | None)) -> Ownership {
    if expr is None {
        return Ownership.UNKNOWN;
    }
    if isinstance(expr, uni.FuncCall) {
        return Ownership.OWNED;
    }
    if isinstance(
        expr, (uni.ListVal, uni.SetVal, uni.DictVal, uni.ListCompr, uni.DictCompr)
    ) {
        return Ownership.OWNED;
    }
    if isinstance(expr, uni.FString) {
        return Ownership.OWNED;
    }
    if isinstance(expr, uni.MultiString) {
        if len(expr.strings) == 1 and not isinstance(expr.strings[0], uni.FString) {
            return Ownership.STATIC;
        }
        return Ownership.OWNED;
    }
    if isinstance(expr, uni.String) {
        return Ownership.STATIC;
    }
    if isinstance(expr, (uni.Name, uni.AtomTrailer)) {
        return Ownership.BORROWED;
    }
    return Ownership.UNKNOWN;
}
