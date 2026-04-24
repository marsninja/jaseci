"""Signal lowering should respect local bindings that shadow `has` fields."""

cl {
    def:pub shadow_demo(items: list) -> JsxElement {
        has count: int = 0;

        inc = lambda count: int -> int {
            return count + 1;
        };

        can with entry {
            print(count.peek());
            count = count + 1;
        }

        for count in items {
            print(count);
        }

        doubled = [count * 2 for count in items if count > 0];
        from_signal = [item for item in count if item > 0];
        nested = [count + item for count in items for item in count if item > 0];

        return <div>{inc(2)}{count}{doubled}{from_signal}{nested}</div>;
    }
}
