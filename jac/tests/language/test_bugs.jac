"""Bug regression tests – migrated from tests/language/test_bugs.py."""

import os;
import from pathlib { Path }
import jaclang;
import from jaclang.jac0core.program { JacProgram }

glob FIXTURES = os.path.join(
         str(Path(jaclang.__file__).parent.parent), "tests", "language", "fixtures"
     );

test "impl match confusion issue" {
    mypass = JacProgram();
    # Counts a specific decl/impl-match diagnostic; type_check would add
    # unrelated diagnostics and change the count.
    mypass.compile(os.path.join(FIXTURES, "impl_match_confused.jac"), type_check=False);
    assert len(mypass.errors_had) == 1;
}
