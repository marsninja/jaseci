"""Random value generator for type-based fake data (non-LLM fallback)."""

import string;
import from typing { Any }

glob _RAND_STR_ALPH: str = string.ascii_letters + string.digits;

def _rand_str(n: int = 12) -> str;

def _is_typed_dict(tp: Any) -> bool;

def _is_namedtuple(tp: Any) -> bool;

def _is_enum(tp: Any) -> bool;

def _safe_subclasses(tp: Any) -> list[type];

def _unwrap_annotated(tp: Any) -> Any;

def _unwrap_newtype(tp: Any) -> Any;

def _choose_from(seq: Any) -> Any;

def _random_primitive(tp: Any) -> Any;

def random_value_for_type(tp: Any, *, _depth: int = 0, _max_depth: int = 10) -> Any;

def returns_fake(func: Any) -> Any;
