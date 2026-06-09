"""Command-surface tests for `jac ai` flag forwarding."""

import from jaclang.cli.agent_api { build_agent_request }


test "build_agent_request forwards ui and tui flags" {
    req = build_agent_request("task", "", 0, False, True, True, False);
    assert req.prompt == "task";
    assert req.quiet is True;
    assert req.ui is True;
    assert req.tui is False;
}
