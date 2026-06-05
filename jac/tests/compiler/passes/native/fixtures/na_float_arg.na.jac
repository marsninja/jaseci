"""Regression lock: a cross-module native call must marshal a float argument by
its real (central) parameter type, not a synthesized all-i64 signature (#6386).

Expected outputs (used by test_native_gen_pass.jac):
  test_cross_module_float()  -> 7.0   (scale(3.5) == 3.5 * 2.0)
"""

import from na_float_arg_lib { scale }

def test_cross_module_float() -> float {
    return scale(3.5);
}
