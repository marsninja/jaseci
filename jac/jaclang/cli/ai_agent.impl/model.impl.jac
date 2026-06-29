import os;
import from pathlib { Path }
import from byllm.lib { Model }
import from byllm.config_loader { get_byllm_config }

impl _byllm_config -> any {
    if agent.ws.cwd {
        return get_byllm_config(Path(agent.ws.cwd));
    }
    return get_byllm_config();
}

impl resolve_model_name(model_override: str = "") -> str {
    flag = model_override.strip();
    if flag {
        agent.cfg.model_source = "command line";
        return flag;
    }

    toml_model = "";
    try {
        raw = _byllm_config().get_jac_config().get_plugin_config("byllm");
        model_section = raw.get("model", {});
        if isinstance(model_section, dict) {
            toml_model = str(model_section.get("default_model", "")).strip();
        }
    } except Exception {
        toml_model = "";
    }
    if toml_model {
        agent.cfg.model_source = "jac.toml";
        return toml_model;
    }
    agent.cfg.model_source = "default";
    return "local:gemma-4-e4b";
}

impl build_model(model_override: str = "", n_ctx: int = 0) -> Model {
    name = resolve_model_name(model_override);
    cfg: dict[str, object] = {};
    is_local = name.startswith("local:");

    agent.cfg.threads = 0;

    agent.cfg.temperature = 0.3 if is_local else None;
    if is_local {
        try {
            cfg = dict(_byllm_config().get_local_config());
        } except Exception {
            cfg = {};
        }

        if not cfg.get("n_threads") {
            cores = os.cpu_count() or 2;
            cfg["n_threads"] = max(1, cores // 2);
        }
        agent.cfg.threads = int(cfg.get("n_threads") or 0);
    } else {
        if agent.cfg.api_key {
            cfg["api_key"] = agent.cfg.api_key;
        }
        if agent.cfg.base_url {
            cfg["base_url"] = agent.cfg.base_url;
        }
    }
    if n_ctx > 0 {
        cfg["n_ctx"] = n_ctx;
    }
    return Model(model_name=name, config=cfg);
}

impl _model_needs_key(name: str) -> tuple[bool, str] {
    if not name or name.startswith("local:") {
        return (False, "");
    }

    if agent.cfg.api_key {
        return (False, "");
    }
    try {
        toml_key = str(_byllm_config().get_model_config().get("api_key", "") or "");
        if toml_key {
            return (False, "");
        }
    } except Exception { }

    try {
        import litellm;

        ll: any = litellm;
        info: any = ll.validate_environment(name);
        if info.get("keys_in_environment") {
            return (False, "");
        }
        missing: list = list(info.get("missing_keys", []) or []);
        for k in missing {
            if str(k).endswith("_API_KEY") {
                return (True, str(k));
            }
        }
    } except Exception { }
    return (False, "");
}

impl _refresh_key_status -> None {
    name = "";
    try {
        name = str(agent_model.model_name);
    } except Exception {
        name = "";
    }
    (needs, env) = _model_needs_key(name);
    agent.bus.needs_key = needs;
    agent.bus.key_env = env;
    agent.bus.model_name = name;
}
