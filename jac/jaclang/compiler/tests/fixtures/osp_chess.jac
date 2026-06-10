"""Cross-backend OSP end-to-end fixture: ospchess (issue #6146 Phase 5).

Object-Spatial chess move-network analysis -- the e2e that exercises the whole
OSP stack at once, at a scale the micro-fixtures don't: a full 8x8 board of 64
`Square` nodes wired with TWO typed edge networks (`Knight`: 336 directed
moves, `King`: 420), then three walkers over it:

  * `Census`  -- per-square knight mobility via `len([->:Knight:->])`
                 (a1 corner = 2, b1 edge = 3, d4 center = 8);
  * `Reach`   -- visit-once DFS over the knight network from a1; the knight
                 graph is connected, so it reaches all 64 squares. The first
                 visited squares pin the kernel's deterministic DFS order;
  * `Hunt`    -- DFS over the king network from a1 (code 0) hunting h8 (63),
                 `report`ing each new square and `disengage`-ing on arrival;
                 reports are delivered onto `w.reports` at the spawn boundary.

Squares are coded `rank * 8 + file` (a1 = 0, h8 = 63). All compared values are
portable ints / int lists -- never backend identity.

Backend status: py and na agree on every value (graph build at scale, typed
edge refs, visit-once guards, report delivery, disengage), so na is enforced.
cl stays unrequired: its spawn lowering only recognizes a target that is a node
constructor or a variable bound to one, so spawning at a square held in a list
(`a1 = squares[0]; w spawn a1;`) lowers to `null` (tracked upstream). Flip to
`require=["na", "cl"]` when that lands.
"""

node Square { has code: int; }

edge Knight {}
edge King {}

walker Census {
    has deg: int = 0;
    can measure with Square entry {
        self.deg = len([->:Knight:->]);
    }
}

walker Reach {
    has seen: list = [];
    can step with Square entry {
        if here.code not in self.seen {
            self.seen.append(here.code);
            visit [->:Knight:->];
        }
    }
}

walker Hunt {
    has target: int = 63, found: int = 0;
    has seen: list = [];
    can step with Square entry {
        if here.code not in self.seen {
            self.seen.append(here.code);
            report here.code;
            if here.code == self.target {
                self.found = 1;
                disengage;
            }
            visit [->:King:->];
        }
    }
}

def build_board_py() -> list {
    squares: list = [];
    for code in range(64) {
        squares.append(Square(code=code));
    }
    drs: list = [1, 2, 2, 1, -1, -2, -2, -1];
    dfs: list = [2, 1, -1, -2, -2, -1, 1, 2];
    krs: list = [1, 1, 1, 0, 0, -1, -1, -1];
    kfs: list = [-1, 0, 1, -1, 1, -1, 0, 1];
    for r in range(8) {
        for f in range(8) {
            src = squares[r * 8 + f];
            for i in range(8) {
                nr = r + drs[i];
                nf = f + dfs[i];
                if nr >= 0 and nr < 8 and nf >= 0 and nf < 8 {
                    src +>: Knight() :+> squares[nr * 8 + nf];
                }
                kr = r + krs[i];
                kf = f + kfs[i];
                if kr >= 0 and kr < 8 and kf >= 0 and kf < 8 {
                    src +>: King() :+> squares[kr * 8 + kf];
                }
            }
        }
    }
    return squares;
}

def ospchess_py() -> dict[str, any] {
    squares = build_board_py();
    a1 = squares[0];
    b1 = squares[1];
    d4 = squares[27];
    c1 = Census();
    c1 spawn a1;
    c2 = Census();
    c2 spawn b1;
    c3 = Census();
    c3 spawn d4;
    r = Reach();
    r spawn a1;
    rs = r.seen;
    h = Hunt();
    h spawn a1;
    hr = h.reports;
    return {
        "deg_a1": c1.deg,
        "deg_b1": c2.deg,
        "deg_d4": c3.deg,
        "reach": len(rs),
        "first": rs[:8],
        "found": h.found,
        "hunt_len": len(hr),
        "hunt_last": hr[len(hr) - 1]
    };
}

na {
    def build_board_na() -> list {
        squares: list = [];
        for code in range(64) {
            squares.append(Square(code=code));
        }
        drs: list = [1, 2, 2, 1, -1, -2, -2, -1];
        dfs: list = [2, 1, -1, -2, -2, -1, 1, 2];
        krs: list = [1, 1, 1, 0, 0, -1, -1, -1];
        kfs: list = [-1, 0, 1, -1, 1, -1, 0, 1];
        for r in range(8) {
            for f in range(8) {
                src = squares[r * 8 + f];
                for i in range(8) {
                    nr = r + drs[i];
                    nf = f + dfs[i];
                    if nr >= 0 and nr < 8 and nf >= 0 and nf < 8 {
                        src +>: Knight() :+> squares[nr * 8 + nf];
                    }
                    kr = r + krs[i];
                    kf = f + kfs[i];
                    if kr >= 0 and kr < 8 and kf >= 0 and kf < 8 {
                        src +>: King() :+> squares[kr * 8 + kf];
                    }
                }
            }
        }
        return squares;
    }

    def ospchess_na() -> dict[str, any] {
        squares = build_board_na();
        c1 = Census();
        c1 spawn squares[0];
        c2 = Census();
        c2 spawn squares[1];
        c3 = Census();
        c3 spawn squares[27];
        r = Reach();
        r spawn squares[0];
        rs = r.seen;
        h = Hunt();
        h spawn squares[0];
        hr = h.reports;
        return {
            "deg_a1": c1.deg,
            "deg_b1": c2.deg,
            "deg_d4": c3.deg,
            "reach": len(rs),
            "first": rs[:8],
            "found": h.found,
            "hunt_len": len(hr),
            "hunt_last": hr[len(hr) - 1]
        };
    }
}

cl {
    def build_board_cl() -> list {
        squares: list = [];
        for code in range(64) {
            squares.append(Square(code=code));
        }
        drs: list = [1, 2, 2, 1, -1, -2, -2, -1];
        dfs: list = [2, 1, -1, -2, -2, -1, 1, 2];
        krs: list = [1, 1, 1, 0, 0, -1, -1, -1];
        kfs: list = [-1, 0, 1, -1, 1, -1, 0, 1];
        for r in range(8) {
            for f in range(8) {
                src = squares[r * 8 + f];
                for i in range(8) {
                    nr = r + drs[i];
                    nf = f + dfs[i];
                    if nr >= 0 and nr < 8 and nf >= 0 and nf < 8 {
                        src +>: Knight() :+> squares[nr * 8 + nf];
                    }
                    kr = r + krs[i];
                    kf = f + kfs[i];
                    if kr >= 0 and kr < 8 and kf >= 0 and kf < 8 {
                        src +>: King() :+> squares[kr * 8 + kf];
                    }
                }
            }
        }
        return squares;
    }

    def ospchess_cl() -> dict[str, any] {
        squares = build_board_cl();
        c1 = Census();
        c1 spawn squares[0];
        c2 = Census();
        c2 spawn squares[1];
        c3 = Census();
        c3 spawn squares[27];
        r = Reach();
        r spawn squares[0];
        rs = r.seen;
        h = Hunt();
        h spawn squares[0];
        hr = h.reports;
        return {
            "deg_a1": c1.deg,
            "deg_b1": c2.deg,
            "deg_d4": c3.deg,
            "reach": len(rs),
            "first": rs[:8],
            "found": h.found,
            "hunt_len": len(hr),
            "hunt_last": hr[len(hr) - 1]
        };
    }
}
