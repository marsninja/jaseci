import from jaclang.cli.browser_engine {
    cmd_open as br_open,
    cmd_navigate as br_navigate,
    cmd_snapshot as br_snapshot,
    cmd_click as br_click,
    cmd_type as br_type,
    cmd_fill as br_fill,
    cmd_press as br_press,
    cmd_get as br_get,
    cmd_eval as br_eval,
    cmd_close as br_close
}

impl BrowseTools._browse_err(e: Exception) -> str {
    msg = str(e);
    if "no live browser" in msg {
        return "ERROR: no browser is open -- call browse_open(url) first.";
    }
    return f"ERROR: {msg}";
}

impl BrowseTools._browse(confirm_msg: str, run: any, clip: bool = False) -> str {
    if confirm_msg and not confirm(confirm_msg) {
        return f"DENIED: the user declined to {confirm_msg}.";
    }
    try {
        out = run();
        return truncate(str(out)) if clip else str(out);
    } except Exception as e {
        return self._browse_err(e);
    }
}

sem BrowseTools.browse_open = "Launch a headless browser (or reuse the one already open) and navigate to a URL. Use this to QA a running web app, then read the page with browse_snapshot. An empty URL opens a blank page.";
sem BrowseTools.browse_open.url = "URL to open, e.g. 'http://localhost:8000'. Empty string opens about:blank.";
impl BrowseTools.browse_open(url: str) -> str {
    return self._browse(
        f"open a browser at {url}" if url else "",
        lambda : br_open(self.session_id, url or None)
    );
}

sem BrowseTools.browse_navigate = "Navigate the open browser to a different URL and wait for it to load.";
sem BrowseTools.browse_navigate.url = "The URL to navigate to.";
impl BrowseTools.browse_navigate(url: str) -> str {
    return self._browse(
        f"navigate the browser to {url}", lambda : br_navigate(self.session_id, url)
    );
}

sem BrowseTools.browse_snapshot = "Read the current page as an accessibility tree. Interactive elements are tagged with @e1/@e2 refs that you pass to browse_click, browse_type, and browse_fill. Call this after navigating, and again after any action that changes the page, to see the new state.";
impl BrowseTools.browse_snapshot -> str {
    return self._browse("", lambda : br_snapshot(self.session_id), clip=True);
}

sem BrowseTools.browse_click = "Click an element with a real, trusted mouse event. Pass an @ref from browse_snapshot (e.g. '@e5') or a CSS selector (e.g. '#submit').";
sem BrowseTools.browse_click.target = "An @ref from browse_snapshot, or a CSS selector.";
impl BrowseTools.browse_click(target: str) -> str {
    return self._browse(
        f"click {target} in the browser", lambda : br_click(self.session_id, target)
    );
}

sem BrowseTools.browse_type = "Focus an element and type text into it as real key events, appending to whatever is already there.";
sem BrowseTools.browse_type.target = "An @ref from browse_snapshot, or a CSS selector.";
sem BrowseTools.browse_type.text = "The text to type.";
impl BrowseTools.browse_type(target: str, text: str) -> str {
    return self._browse(
        f"type into {target} in the browser",
        lambda : br_type(self.session_id, target, text)
    );
}

sem BrowseTools.browse_fill = "Clear a field and set its value to the given text. Prefer this over browse_type for form fields.";
sem BrowseTools.browse_fill.target = "An @ref from browse_snapshot, or a CSS selector.";
sem BrowseTools.browse_fill.text = "The text to set the field to.";
impl BrowseTools.browse_fill(target: str, text: str) -> str {
    return self._browse(
        f"fill {target} in the browser", lambda : br_fill(self.session_id, target, text)
    );
}

sem BrowseTools.browse_press = "Press a single key in the browser, e.g. 'Enter', 'Tab', 'Escape', or a chord like 'Ctrl+A'.";
sem BrowseTools.browse_press.key = "The key or chord to press.";
impl BrowseTools.browse_press(key: str) -> str {
    return self._browse(
        f"press {key} in the browser", lambda : br_press(self.session_id, key)
    );
}

sem BrowseTools.browse_get = "Read a property of the current page: 'url', 'title', or 'text' (the visible text of the element named by selector).";
sem BrowseTools.browse_get.what = "One of 'url', 'title', or 'text'.";
sem BrowseTools.browse_get.selector = "CSS selector for 'text'; empty string for 'url' or 'title'.";
impl BrowseTools.browse_get(what: str, selector: str) -> str {
    return self._browse(
        "", lambda : br_get(self.session_id, what, selector or None), clip=True
    );
}

sem BrowseTools.browse_eval = "Evaluate a JavaScript expression in the page and return its result. Use this to inspect page state or check for errors, e.g. \"document.querySelectorAll('.error').length\".";
sem BrowseTools.browse_eval.expression = "A JavaScript expression to evaluate.";
impl BrowseTools.browse_eval(expression: str) -> str {
    return self._browse(
        f"run JavaScript in the browser: {expression}",
        lambda : br_eval(self.session_id, expression),
        clip=True
    );
}

sem BrowseTools.browse_close = "Close the browser and free its resources. Call this when finished with browser QA.";
impl BrowseTools.browse_close -> str {
    return self._browse("", lambda : br_close(self.session_id));
}

impl BrowseTools._browse_shutdown{
    try {
        br_close(self.session_id);
    } except Exception { }
}
