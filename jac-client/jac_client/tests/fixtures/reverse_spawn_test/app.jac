"""Test module for reverse spawn operator in client code."""

# Server-side node and walker definitions
node TestNode {
    has value: int = 0;
}

walker test_walker {
    has message: str = "Hello";

    can execute with TestNode entry {
        report {"result": self.message, "node_value": here.value};
    }
}

# Client-side code using reverse spawn operator
cl import from react {useState, useEffect}

cl {
    def app() -> any {
        let [result, setResult] = useState(None);

        # Use reverse spawn operator: walker() spawn node
        async def loadData() -> None {
            # Test reverse spawn: walker on left, root on right
            # In client code, you typically spawn on root or a node reference
            data = test_walker(message="Reverse spawn!") spawn root;
            setResult(data);
        }

        useEffect(lambda -> None {
            loadData();
        }, []);

        return <div>
            <h1>Reverse Spawn Test</h1>
            <div>Result: {JSON.stringify(result)}</div>
        </div>;
    }
}
