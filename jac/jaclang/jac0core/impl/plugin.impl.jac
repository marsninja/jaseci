"""Implementation for plugin system."""

impl HookimplMarker.__call__(function: _F) -> _F {
    setattr(function, _IMPL_ATTR, True);
    return function;
}

impl HookspecMarker.__call__(
    function: (_F | None) = None, *, firstresult: bool = False
) -> (_F | Callable[([_F], _F)]) {
    def mark(func: _F) -> _F {
        setattr(func, _SPEC_ATTR, {'firstresult': firstresult});
        return func;
    }
    if function is not None {
        return mark(function);
    }
    return mark;
}

impl HookImpl.__repr__ -> str {
    return f"<HookImpl plugin_name={self.plugin_name!r}>";
}

impl HookCaller._add_hookimpl(hi: HookImpl) -> None {
    self._hookimpls.append(hi);
}

impl HookCaller._remove_plugin(plugin: object) -> None {
    self._hookimpls = [
        h
        for h in self._hookimpls
        if h.plugin is not plugin
    ];
}

impl HookCaller.get_hookimpls -> list[HookImpl] {
    return `list(self._hookimpls);
}

impl HookCaller._call_impl(hi: HookImpl, kwargs: dict[(str, object)]) -> object {
    if hi.argnames is None {
        return hi.function(**kwargs);
    }
    return hi.function(
        **{
            name: kwargs[name]
            for name in hi.argnames
            if name in kwargs
        }
    );
}

impl HookCaller.__call__(**kwargs: object) -> object {
    if self._firstresult {
        for hi in reversed(self._hookimpls) {
            result = self._call_impl(hi, kwargs);
            if result is not None {
                return result;
            }
        }
        return None;
    }
    results: list[Any] = [];
    for hi in reversed(self._hookimpls) {
        result = self._call_impl(hi, kwargs);
        if result is not None {
            results.append(result);
        }
    }
    return results;
}

impl HookCaller.__repr__ -> str {
    return f"<HookCaller {self.name!r}>";
}

impl LazyHookCaller._ensure_loaded -> None {
    if self._loaded {
        return;
    }
    with self._lock {
        if self._loaded {
            return;
        }
        self._loaded = True;
        pending = `list(self._pending);
        self._pending = [];
        for pep in pending {
            if pep.name in self._disabled {
                continue;
            }
            try {
                plugin_cls = pep.load();
                if self._pm is not None {
                    self._pm.register(plugin_cls, name=pep.name);
                    dist = getattr(pep, 'dist', None);
                    if dist is not None {
                        self._pm._plugin_distinfo.append(
                            (plugin_cls, _DistFacade(_dist=dist))
                        );
                    }
                }
            } except Exception {
                ;
            }
        }
    }
}

impl LazyHookCaller.__call__(**kwargs: object) -> object {
    self._ensure_loaded();
    return super.__call__(**kwargs);
}

impl PluginManager.register(plugin: object, name: (str | None) = None) -> (str | None) {
    plugin_name = name or _canonical_name(plugin);
    if id(plugin) in self._plugin2name {
        return None;
    }
    self._name2plugin[plugin_name] = plugin;
    self._plugin2name[id(plugin)] = plugin_name;
    self._lazy_entrypoints.pop(plugin_name, None);
    seen: set[str] = `set();
    for klass in inspect.getmro(
        `type(plugin) if not isinstance(plugin, type) else plugin
    ) {
        for (attr_name, raw) in vars(klass).items() {
            if attr_name in seen {
                continue;
            }
            seen.add(attr_name);
            func = (
                raw.__func__ if isinstance(raw, (classmethod, staticmethod)) else raw
            );
            if not callable(func) {
                continue;
            }
            if not getattr(func, _IMPL_ATTR, False) {
                continue;
            }
            method = getattr(plugin, attr_name, None);
            if method is None {
                continue;
            }

            hi = HookImpl(
                function=method,
                plugin=plugin,
                plugin_name=plugin_name,
                argnames=_get_argnames(method)
            );

            hook: (HookCaller | None) = getattr(self.hook, attr_name, None);
            if hook is None {
                hook = HookCaller(attr_name, _firstresult=False);
                setattr(self.hook, attr_name, hook);
            }
            hook._add_hookimpl(hi);
        }
    }
    return plugin_name;
}

impl PluginManager.unregister(
    plugin: (object | None) = None, name: (str | None) = None
) -> (object | None) {
    if plugin is None and name is not None {
        plugin = self._name2plugin.get(name);
    }
    if plugin is None {
        return None;
    }
    plugin_name = self._plugin2name.pop(id(plugin), None);
    if plugin_name is not None {
        self._name2plugin.pop(plugin_name, None);
    }
    if name is not None and name != plugin_name {
        self._name2plugin.pop(name, None);
    }
    for attr_name in `list(vars(self.hook)) {
        hook = getattr(self.hook, attr_name, None);
        if isinstance(hook, HookCaller) {
            hook._remove_plugin(plugin);
        }
    }
    return plugin;
}

impl PluginManager.is_registered(plugin: object) -> bool {
    return id(plugin) in self._plugin2name;
}

impl PluginManager.add_hookspecs(spec_class: type) -> None {
    for attr_name in dir(spec_class) {
        method = getattr(spec_class, attr_name, None);
        if method is None {
            continue;
        }
        spec_opts = getattr(method, _SPEC_ATTR, None);
        if spec_opts is None {
            continue;
        }

        firstresult = spec_opts.get('firstresult', False);
        hook: (HookCaller | None) = getattr(self.hook, attr_name, None);
        if hook is None {
            hook = HookCaller(attr_name, _firstresult=firstresult);
            setattr(self.hook, attr_name, hook);
        } else {
            hook._firstresult = firstresult;
        }
    }
}

impl PluginManager.list_name_plugin -> list[tuple[(str, object)]] {
    return `list(self._name2plugin.items());
}

impl PluginManager.list_plugin_distinfo -> list[tuple[(object, Any)]] {
    return `list(self._plugin_distinfo);
}

impl PluginManager.list_all_plugins -> list[tuple[(str, (object | None), Any)]] {
    result: list[tuple[(str, (object | None), Any)]] = [];
    # Build a lookup from plugin object to dist info.
    dist_by_id: dict[int, Any] = {};
    for (p, d) in self._plugin_distinfo {
        dist_by_id[id(p)] = d;
    }
    # Loaded plugins.
    for (name, plugin) in self._name2plugin.items() {
        dist_info = dist_by_id.get(id(plugin));
        result.append((name, plugin, dist_info));
    }
    # Pending lazy plugins (not yet loaded).
    for (name, ep) in self._lazy_entrypoints.items() {
        if name not in self._name2plugin {
            dist = getattr(ep, 'dist', None);
            dist_facade = _DistFacade(_dist=dist) if dist is not None else None;
            result.append((name, None, dist_facade));
        }
    }
    return result;
}

impl PluginManager.register_lazy_entrypoint(
    ep: object, hook_names: (list | None) = None, disabled: (list | None) = None
) -> None {
    disabled_list = disabled if disabled is not None else [];
    # No hook manifest → eager fallback (backwards compat).
    if hook_names is None {
        if ep.name not in disabled_list {
            try {
                plugin = ep.load();
                self.register(plugin, name=ep.name);
                dist = getattr(ep, 'dist', None);
                if dist is not None {
                    self._plugin_distinfo.append((plugin, _DistFacade(_dist=dist)));
                }
            } except Exception {
                ;
            }
        }
        return;
    }
    # Track the entry point for discovery by list_all_plugins.
    self._lazy_entrypoints[ep.name] = ep;
    # Lazy path: attach EP as pending on LazyHookCallers.
    for hook_name in hook_names {
        hook = getattr(self.hook, hook_name, None);
        if hook is None or not isinstance(hook, LazyHookCaller) {
            lazy_hook = LazyHookCaller(hook_name, _firstresult=True, _pm=self);
            lazy_hook._disabled = disabled_list;
            # Preserve existing hookimpls from the original HookCaller.
            if hook is not None {
                for hi in hook.get_hookimpls() {
                    lazy_hook._add_hookimpl(hi);
                }
            }
            setattr(self.hook, hook_name, lazy_hook);
            hook = lazy_hook;
        }
        hook._pending.append(ep);
    }
}

impl PluginManager.load_setuptools_entrypoints(group: str) -> int {
    count = 0;
    for dist in importlib.metadata.distributions() {
        for ep in dist.entry_points {
            if ep.group != group {
                continue;
            }
            if ep.name in self._name2plugin {
                continue;
            }
            try {
                plugin = ep.load();
            } except Exception {
                continue;
            }
            self.register(plugin, name=ep.name);
            self._plugin_distinfo.append((plugin, _DistFacade(_dist=dist)));
            count += 1;
        }
    }
    return count;
}

@property
impl _DistFacade.project_name -> str {
    return self._dist.metadata['Name'];
}

@property
impl _DistFacade.version -> str {
    return self._dist.metadata.get('Version', '0.0.0');
}

impl _DistFacade.__getattr__(attr: str) -> object {
    return getattr(self._dist, attr);
}
