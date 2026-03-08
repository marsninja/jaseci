"""Tests for has-level properties (get/set) language feature."""

# ── Basic getter ─────────────────────────────────────────────

obj WithGetter {
    has name: str = "alice"
        get { return name.upper(); };
}

test "basic getter transforms value on read" {
    w = WithGetter();
    assert w.name == "ALICE";
}

test "getter is called on every access" {
    w = WithGetter();
    _ = w.name;
    _ = w.name;
    assert w.name == "ALICE";
}

# ── Basic setter ─────────────────────────────────────────────

obj WithSetter {
    has score: int = 0
        set(value) {
            if value < 0 { score = 0; }
            else { score = value; }
        };
}

test "basic setter clamps negative to zero" {
    w = WithSetter();
    w.score = -10;
    assert w.score == 0;
}

test "setter allows valid values" {
    w = WithSetter();
    w.score = 42;
    assert w.score == 42;
}

test "setter applies on construction" {
    w = WithSetter(score=-5);
    assert w.score == 0;
}

# ── Getter and setter together ───────────────────────────────

obj Temperature {
    has celsius: float = 0.0;

    has fahrenheit: float
        get { return self.celsius * 9.0 / 5.0 + 32.0; }
        set(value) { self.celsius = (value - 32.0) * 5.0 / 9.0; };
}

test "computed getter derives from another field" {
    t = Temperature(celsius=100.0);
    assert t.fahrenheit == 212.0;
}

test "setter updates backing field through another field" {
    t = Temperature();
    t.fahrenheit = 212.0;
    assert t.celsius == 100.0;
}

test "getter and setter are symmetric" {
    t = Temperature();
    t.fahrenheit = 72.0;
    assert abs(t.fahrenheit - 72.0) < 0.001;
}

# ── Read-only property (getter only, no setter) ─────────────

obj Rectangle {
    has width: float = 0.0,
        height: float = 0.0;

    has area: float
        get { return self.width * self.height; };

    has perimeter: float
        get { return 2.0 * (self.width + self.height); };
}

test "read-only property computes from other fields" {
    r = Rectangle(width=3.0, height=4.0);
    assert r.area == 12.0;
    assert r.perimeter == 14.0;
}

test "read-only property reflects changes to source fields" {
    r = Rectangle(width=1.0, height=1.0);
    assert r.area == 1.0;
    r.width = 5.0;
    assert r.area == 5.0;
    r.height = 10.0;
    assert r.area == 50.0;
}

test "assigning to read-only property raises error" {
    r = Rectangle(width=3.0, height=4.0);
    got_error = False;
    try {
        r.area = 99.0;
    } except AttributeError {
        got_error = True;
    }
    assert got_error;
}

# ── Setter with validation ───────────────────────────────────

obj Account {
    has balance: float = 0.0
        set(value) {
            if value < 0 {
                raise ValueError("Balance cannot be negative");
            }
            balance = value;
        };
}

test "setter validation rejects invalid value" {
    a = Account();
    got_error = False;
    try {
        a.balance = -100.0;
    } except ValueError {
        got_error = True;
    }
    assert got_error;
    assert a.balance == 0.0;
}

test "setter validation accepts valid value" {
    a = Account(balance=500.0);
    assert a.balance == 500.0;
    a.balance = 1000.0;
    assert a.balance == 1000.0;
}

# ── Setter with side effects ─────────────────────────────────

obj Tracked {
    has change_count: int = 0;
    has value: int = 0
        set(new_val) {
            value = new_val;
            self.change_count += 1;
        };
}

test "setter side effects update other fields" {
    t = Tracked();
    t.value = 10;
    t.value = 20;
    t.value = 30;
    assert t.value == 30;
    assert t.change_count == 3;
}

# ── Getter with formatting / transformation ──────────────────

obj User {
    has first_name: str = "",
        last_name: str = "";

    has full_name: str
        get { return f"{self.first_name} {self.last_name}".strip(); }
        set(value) {
            parts = value.split(" ", 1);
            self.first_name = parts[0];
            self.last_name = parts[1] if len(parts) > 1 else "";
        };

    has email: str = ""
        get { return email.lower(); }
        set(value) { email = value.strip().lower(); };
}

test "computed full_name from parts" {
    u = User(first_name="Jane", last_name="Doe");
    assert u.full_name == "Jane Doe";
}

test "setting full_name splits into parts" {
    u = User();
    u.full_name = "John Smith";
    assert u.first_name == "John";
    assert u.last_name == "Smith";
}

test "full_name handles single name" {
    u = User();
    u.full_name = "Madonna";
    assert u.first_name == "Madonna";
    assert u.last_name == "";
}

test "email getter normalizes case" {
    u = User();
    u.email = "  Alice@Example.COM  ";
    assert u.email == "alice@example.com";
}

# ── Inheritance with properties ──────────────────────────────

obj Base {
    has value: int = 0
        get { return value * 2; };
}

obj Child(Base) {
    has extra: int = 0;
}

obj OverrideChild(Base) {
    has value: int = 0
        get { return value * 10; };
}

test "child inherits parent getter" {
    c = Child(value=5, extra=1);
    assert c.value == 10;
}

test "child can override parent getter" {
    oc = OverrideChild(value=5);
    assert oc.value == 50;
}

# ── Property on node archetype ───────────────────────────────

node SensorNode {
    has raw_reading: float = 0.0,
        calibration_offset: float = 0.0;

    has calibrated: float
        get { return self.raw_reading + self.calibration_offset; };
}

test "property works on node archetype" {
    s = SensorNode(raw_reading=25.3, calibration_offset=-1.2);
    assert abs(s.calibrated - 24.1) < 0.001;
}

# ── Property on walker archetype ─────────────────────────────

walker Collector {
    has items: list[str] = [];

    has count: int
        get { return len(self.items); };
}

test "property works on walker archetype" {
    c = Collector(items=["a", "b", "c"]);
    assert c.count == 3;
}

# ── Bool property ────────────────────────────────────────────

obj Container {
    has items: list[int] = [];

    has is_empty: bool
        get { return len(self.items) == 0; };

    has size: int
        get { return len(self.items); };
}

test "bool computed property" {
    c = Container();
    assert c.is_empty;
    assert c.size == 0;
    c.items.append(1);
    assert not c.is_empty;
    assert c.size == 1;
}

# ── Chained property access ─────────────────────────────────

obj Inner {
    has x: int = 0
        get { return x + 1; };
}

obj Outer {
    has inner: Inner = Inner();

    has x_plus_one: int
        get { return self.inner.x; };
}

test "chained property access through nested objects" {
    o = Outer(inner=Inner(x=10));
    assert o.inner.x == 11;
    assert o.x_plus_one == 11;
}

# ── Impl block with properties ──────────────────────────────

obj Shape {
    has:priv _sides: int = 0;

    has sides: int
        get;
        set;
}

impl Shape.sides {
    get { return _sides; }
    set(value) {
        if value < 3 { raise ValueError("Need at least 3 sides"); }
        _sides = value;
    }
}

test "impl block getter works" {
    s = Shape(sides=4);
    assert s.sides == 4;
}

test "impl block setter validates" {
    got_error = False;
    try {
        s = Shape(sides=2);
    } except ValueError {
        got_error = True;
    }
    assert got_error;
}

# ── Separate impl file pattern (forward declaration) ────────

obj Config {
    has raw_debug: str = "false";

    has debug: bool
        get;
        set;
}

impl Config.debug {
    get { return self.raw_debug.lower() in ["true", "1", "yes"]; }
    set(value) { self.raw_debug = "true" if value else "false"; }
}

test "forward-declared property with impl block" {
    c = Config();
    assert not c.debug;
    c.debug = True;
    assert c.debug;
    assert c.raw_debug == "true";
    c.debug = False;
    assert c.raw_debug == "false";
}

# ── Property with type coercion in setter ────────────────────

obj StrictInt {
    has value: int = 0
        set(v) {
            value = int(v);
        };
}

test "setter coerces type" {
    s = StrictInt();
    s.value = 3.7;
    assert s.value == 3;
    assert type(s.value) == int;
}

# ── Multiple properties on same object ───────────────────────

obj Range {
    has lo: int = 0
        set(value) {
            if value > self.hi { raise ValueError("lo must be <= hi"); }
            lo = value;
        };

    has hi: int = 100
        set(value) {
            if value < self.lo { raise ValueError("hi must be >= lo"); }
            hi = value;
        };

    has span: int
        get { return self.hi - self.lo; };
}

test "multiple validated properties on same object" {
    r = Range(lo=10, hi=50);
    assert r.span == 40;
}

test "cross-field validation in setter" {
    r = Range(lo=0, hi=100);
    got_error = False;
    try {
        r.lo = 200;
    } except ValueError {
        got_error = True;
    }
    assert got_error;
    assert r.lo == 0;
}

# ── Getter-only with no backing storage ──────────────────────

obj Clock {
    has hours: int = 0,
        minutes: int = 0;

    has display: str
        get { return f"{self.hours:02d}:{self.minutes:02d}"; };
}

test "purely computed property with no storage" {
    c = Clock(hours=9, minutes=5);
    assert c.display == "09:05";
    c.hours = 14;
    c.minutes = 30;
    assert c.display == "14:30";
}

# ── Property used in string formatting and expressions ───────

obj Product {
    has price: float = 0.0,
        tax_rate: float = 0.1;

    has total: float
        get { return self.price * (1.0 + self.tax_rate); };
}

test "property in arithmetic expression" {
    p = Product(price=100.0, tax_rate=0.2);
    assert p.total == 120.0;
    double = p.total * 2;
    assert double == 240.0;
}

test "property in f-string" {
    p = Product(price=50.0, tax_rate=0.1);
    s = f"Total: {p.total}";
    assert s == "Total: 55.0";
}

# ── Edge case: default value goes through setter ─────────────

obj Clamped {
    has x: int = 150
        set(value) {
            if value > 100 { x = 100; }
            elif value < 0 { x = 0; }
            else { x = value; }
        };
}

test "default value is processed by setter" {
    c = Clamped();
    assert c.x == 100;
}

test "clamped setter works on subsequent assignments" {
    c = Clamped();
    c.x = -50;
    assert c.x == 0;
    c.x = 75;
    assert c.x == 75;
    c.x = 999;
    assert c.x == 100;
}
