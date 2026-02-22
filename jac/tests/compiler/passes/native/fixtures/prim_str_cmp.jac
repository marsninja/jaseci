"""String comparison primitives: <, >, <=, >=.

Cross-backend equivalence fixture — Python reference + native implementation.
"""

def str_cmp_py() -> dict {
    return {
        # Less than
        "lt_abc_def": 1 if "abc" < "def" else 0,
        "lt_def_abc": 1 if "def" < "abc" else 0,
        "lt_same": 1 if "abc" < "abc" else 0,
        "lt_prefix": 1 if "abc" < "abcd" else 0,
        "lt_empty": 1 if "" < "a" else 0,
        # Greater than
        "gt_abc_def": 1 if "abc" > "def" else 0,
        "gt_def_abc": 1 if "def" > "abc" else 0,
        "gt_same": 1 if "abc" > "abc" else 0,
        "gt_longer": 1 if "abcd" > "abc" else 0,
        # Less or equal
        "le_abc_def": 1 if "abc" <= "def" else 0,
        "le_same": 1 if "abc" <= "abc" else 0,
        "le_def_abc": 1 if "def" <= "abc" else 0,
        # Greater or equal
        "ge_abc_def": 1 if "abc" >= "def" else 0,
        "ge_same": 1 if "abc" >= "abc" else 0,
        "ge_def_abc": 1 if "def" >= "abc" else 0
    };
}

na {
    def str_cmp_na() -> dict[str, any] {
        lt_ad: int = 0;
        if "abc" < "def" { lt_ad = 1; }
        lt_da: int = 0;
        if "def" < "abc" { lt_da = 1; }
        lt_same: int = 0;
        if "abc" < "abc" { lt_same = 1; }
        lt_pfx: int = 0;
        if "abc" < "abcd" { lt_pfx = 1; }
        lt_empty: int = 0;
        if "" < "a" { lt_empty = 1; }
        gt_ad: int = 0;
        if "abc" > "def" { gt_ad = 1; }
        gt_da: int = 0;
        if "def" > "abc" { gt_da = 1; }
        gt_same: int = 0;
        if "abc" > "abc" { gt_same = 1; }
        gt_longer: int = 0;
        if "abcd" > "abc" { gt_longer = 1; }
        le_ad: int = 0;
        if "abc" <= "def" { le_ad = 1; }
        le_same: int = 0;
        if "abc" <= "abc" { le_same = 1; }
        le_da: int = 0;
        if "def" <= "abc" { le_da = 1; }
        ge_ad: int = 0;
        if "abc" >= "def" { ge_ad = 1; }
        ge_same: int = 0;
        if "abc" >= "abc" { ge_same = 1; }
        ge_da: int = 0;
        if "def" >= "abc" { ge_da = 1; }
        return {
            "lt_abc_def": lt_ad,
            "lt_def_abc": lt_da,
            "lt_same": lt_same,
            "lt_prefix": lt_pfx,
            "lt_empty": lt_empty,
            "gt_abc_def": gt_ad,
            "gt_def_abc": gt_da,
            "gt_same": gt_same,
            "gt_longer": gt_longer,
            "le_abc_def": le_ad,
            "le_same": le_same,
            "le_def_abc": le_da,
            "ge_abc_def": ge_ad,
            "ge_same": ge_same,
            "ge_def_abc": ge_da
        };
    }
}
