"""Test module for spawn operator in both standard and reverse order."""

# Server-side node and walker definitions
node TestNode {
    has value: int = 0;
}

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

# Client-side code testing both spawn orderings
cl import from react {useState, useEffect}

cl {
    def app() -> any {
        let [standardResult, setStandardResult] = useState(None);
        let [standardComputed, setStandardComputed] = useState(None);
        let [reverseResult, setReverseResult] = useState(None);

        async def loadData() -> None {
            # Test standard spawn order: node spawn walker()
            data1 = root spawn test_walker();
            setStandardResult(data1);

            data2 = root spawn parameterized_walker(value=42);
            setStandardComputed(data2);

            # Test reverse spawn order: walker() spawn node
            data3 = test_walker(message="Reverse spawn!") spawn root;
            setReverseResult(data3);
        }

        useEffect(lambda -> None {
            loadData();
        }, []);

        return <div>
            <h1>Spawn Operator Test</h1>
            <h2>Standard Order (node spawn walker)</h2>
            <div>Result: {JSON.stringify(standardResult)}</div>
            <div>Computed: {JSON.stringify(standardComputed)}</div>
            <h2>Reverse Order (walker spawn node)</h2>
            <div>Result: {JSON.stringify(reverseResult)}</div>
        </div>;
    }
}
