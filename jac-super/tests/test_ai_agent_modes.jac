"""Tests for `jac ai` mode selection and adapter registry."""

import from jaclang.cli.agent_api { build_agent_request }
import from jac_super.ai_modes.registry { get_ai_mode_registry }
import from jac_super.ai_modes.register { register_modes }


test "mode selection defaults to plain" {
    register_modes();
    req = build_agent_request("", "", 0, False, False, False, False);
    mode = get_ai_mode_registry().select(req);
    assert type(mode).__name__ == "PlainMode";
}


test "mode selection chooses web when ui flag is set" {
    register_modes();
    req = build_agent_request("", "", 0, False, False, True, False);
    mode = get_ai_mode_registry().select(req);
    assert type(mode).__name__ == "WebMode";
}


test "mode selection chooses tui when tui flag is set" {
    register_modes();
    req = build_agent_request("", "", 0, False, False, False, True);
    mode = get_ai_mode_registry().select(req);
    assert type(mode).__name__ == "TuiMode";
}


test "mode selection rejects ui+tui conflict" {
    register_modes();
    req = build_agent_request("", "", 0, False, False, True, True);
    try {
        _ = get_ai_mode_registry().select(req);
        assert False;
    } except ValueError as e {
        assert "mutually exclusive" in str(e);
    }
}
