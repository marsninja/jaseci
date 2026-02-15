"""Test impl with event clause parsing."""

nd Item {
    has val: int;
}

walker Visitor {
    can visit_item with Item entry;
}

impl Visitor.visit_item with Item entry {
    print(here.val);
}
