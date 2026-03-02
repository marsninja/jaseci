"""Test that str is accepted where PathLike is expected."""
import from os { PathLike }

def process_path(p: PathLike) -> None {}

with entry {
    # str should be accepted as PathLike -- OK
    process_path("/tmp/test.txt");

    # int should NOT be accepted as PathLike -- Error
    process_path(42);  # <-- Error
}
