"""Minimal app with walker:priv for testing 401 auto-logout."""

node SecretNote {
    has text: str;
}

walker:priv get_notes {
    has items: list = [];

    can start with Root entry {
        visit [-->];
    }

    can collect with SecretNote entry {
        self.items.append({"text": here.text});
    }

    can done with Root exit {
        report self.items;
    }
}

walker:priv add_note {
    has text: str;

    can create with Root entry {
        new_note = here ++> SecretNote(text=self.text);
        report {"text": new_note[0].text};
    }
}

cl {
    import from "@jac/runtime" { jacSignup, jacLogin, jacLogout, jacIsLoggedIn }

    def:pub app -> JsxElement {
        has isLoggedIn: bool = False,
            checkingAuth: bool = True,
            isSignup: bool = False,
            username: str = "",
            password: str = "",
            error: str = "",
            loading: bool = False,
            notes: list = [],
            notesLoading: bool = True;

        can with entry {
            isLoggedIn = jacIsLoggedIn();
            checkingAuth = False;
        }

        can with [isLoggedIn] entry {
            if isLoggedIn {
                fetchNotes();
            }
        }

        async def fetchNotes -> None {
            notesLoading = True;
            result = root spawn get_notes();
            notes = result.reports[0] if result.reports else [];
            notesLoading = False;
        }

        async def handleLogin -> None {
            error = "";
            if not username.strip() or not password {
                error = "Please fill in all fields";
                return;
            }
            loading = True;
            success = await jacLogin(username, password);
            loading = False;
            if success {
                isLoggedIn = True;
                username = "";
                password = "";
            } else {
                error = "Invalid credentials";
            }
        }

        async def handleSignup -> None {
            error = "";
            if not username.strip() or not password {
                error = "Please fill in all fields";
                return;
            }
            loading = True;
            result = await jacSignup(username, password);
            loading = False;
            if result["success"] {
                isLoggedIn = True;
                username = "";
                password = "";
            } else {
                error = result["error"] if result["error"] else "Signup failed";
            }
        }

        def handleLogout -> None {
            jacLogout();
            isLoggedIn = False;
            notes = [];
        }

        async def handleSubmit(e: any) -> None {
            e.preventDefault();
            if isSignup { await handleSignup(); }
            else { await handleLogin(); }
        }

        if checkingAuth {
            return <div class="loading">Loading...</div>;
        }

        if isLoggedIn {
            return
                <div>
                    <h1>Private Notes</h1>
                    <button id="logout-btn" onClick={handleLogout}>Logout</button>
                    {(
                        <div id="notes-loading">Loading notes...</div>
                    ) if notesLoading else (
                        <div id="notes-list">
                            {(
                                <div id="notes-empty">No notes yet.</div>
                            ) if len(notes) == 0 else (
                                <div>
                                    {[
                                        <div key={n.text} class="note">{n.text}</div>
                                        for n in notes
                                    ]}
                                </div>
                            )}
                        </div>
                    )}
                </div>;
        }

        return
            <div>
                <h1 id="login-title">
                    {("Create Account" if isSignup else "Sign In")}
                </h1>
                {(
                    <div id="auth-error">{error}</div>
                ) if error else None}
                <form onSubmit={handleSubmit}>
                    <input
                        type="text"
                        id="username-input"
                        value={username}
                        onChange={lambda e: any -> None { username = e.target.value; }}
                        placeholder="Username"
                    />
                    <input
                        type="password"
                        id="password-input"
                        value={password}
                        onChange={lambda e: any -> None { password = e.target.value; }}
                        placeholder="Password"
                    />
                    <button type="submit" id="submit-btn" disabled={loading}>
                        {(
                            "Processing..."
                            if loading
                            else ("Create Account" if isSignup else "Sign In")
                        )}
                    </button>
                </form>
                <button
                    id="toggle-auth"
                    onClick={lambda -> None { isSignup = not isSignup; error = ""; }}
                >
                    {("Sign In" if isSignup else "Sign Up")}
                </button>
            </div>;
    }
}
