"""Fixture for issue #7158: `Any` must absorb inside a union.

`typing.Any` used as an annotation resolves to the `Any` class (not the
internal `AnyType`). Union handling must recognize that form as a wildcard:

  * attribute access on `T | ... | Any` validates only the non-`Any`
    members and yields `result | Any` -- it must NOT report the attribute
    "missing from Any".
  * a union containing `Any` is assignable wherever its non-`Any` members
    are assignable -- the `Any` member absorbs.

Every function below is well-typed and must produce zero errors.
"""

import from typing { Any }

obj Base {}

obj Alpha(Base) {
    has tag: str = "a";
}

obj Beta(Base) {
    has tag: str = "b";
}

def attr_on_union_with_any(pick: bool, alt: Any) -> str {
    # `Alpha | Any` -- `.tag` exists on Alpha; Any absorbs, no "missing" error.
    item = Alpha() if pick else alt;
    return item.tag;
}

def take_base_or_none(x: Base | None) -> None {}

def assign_union_with_any(
    u: bool, a: Alpha, b: Beta, anyv: Any
) -> None {
    # `Alpha | Beta | Any` assigned to `Base | None`: Alpha/Beta are subtypes
    # of Base and Any absorbs, so the whole union is assignable.
    val = a if u else (b if u else anyv);
    take_base_or_none(val);
}
