"""Test module for spawn operator in client code."""

# Server-side walker definitions
walker test_walker {
    has message: str = "Hello from walker";

    can execute with `root entry {
        report {"result": self.message};
    }
}

walker parameterized_walker {
    has value: int;

    can execute with `root entry {
        report {"computed": self.value * 2};
    }
}

# Client-side code using spawn operator
cl import from react {useState, useEffect}

cl {
    def app() -> any {
        let [result, setResult] = useState(None);
        let [computed, setComputed] = useState(None);

        # Use spawn operator to call walker on root
        async def loadData() -> None {
            # Test spawn operator with simple walker
            data1 = await root spawn test_walker();
            setResult(data1);

            # Test spawn operator with parameterized walker
            data2 = await root spawn parameterized_walker(value=42);
            setComputed(data2);
        }

        useEffect(lambda -> None {
            loadData();
        }, []);

        return <div>
            <h1>Spawn Operator Test</h1>
            <div>Result: {JSON.stringify(result)}</div>
            <div>Computed: {JSON.stringify(computed)}</div>
        </div>;
    }
}
