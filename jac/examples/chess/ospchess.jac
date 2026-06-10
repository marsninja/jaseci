"""ospchess -- Object-Spatial chess move-network analysis (issue #6146).

The chess board as a graph: 64 `Square` nodes wired with two typed edge
networks (`Knight`: 336 directed moves, `King`: 420), analyzed by walkers
instead of loops over arrays:

  * `Census`  measures a square's knight mobility with a typed edge ref
              (`len([->:Knight:->])`) -- corner 2, edge 3, center 8;
  * `Reach`   runs a visit-once DFS over the knight network, proving the
              knight graph is connected (all 64 squares from a1);
  * `Hunt`    DFS-walks the king network from a1 hunting h8, `report`ing each
              new square and `disengage`-ing on arrival; the collected
              reports come back on `w.reports` at the spawn boundary.

The same program compiles on the server (py/sv) and native (LLVM) backends
through the portable osp_kernel -- the cross-backend equivalence fixture
`osp_chess.jac` in the compiler test suite asserts both produce identical
results. Squares are coded `rank * 8 + file` (a1 = 0, h8 = 63).

Run with: jac run ospchess.jac
"""

node Square {
    has code: int;
}

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
    has target: int = 63,
        found: int = 0,
        seen: list = [];

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

def build_board -> list {
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
                    src +>:Knight():+> squares[nr * 8 + nf];
                }
                kr = r + krs[i];
                kf = f + kfs[i];
                if kr >= 0 and kr < 8 and kf >= 0 and kf < 8 {
                    src +>:King():+> squares[kr * 8 + kf];
                }
            }
        }
    }
    return squares;
}

glob squares = build_board(),
     a1 = squares[0],
     b1 = squares[1],
     d4 = squares[27],
     c1 = Census();

with entry {
    c1 spawn a1;
}

glob c2 = Census();

with entry {
    c2 spawn b1;
}

glob c3 = Census();

with entry {
    c3 spawn d4;
    print(f"knight mobility: a1={c1.deg} b1={c2.deg} d4={c3.deg}");
}

glob r = Reach();

with entry {
    r spawn a1;
    print(f"knight network reaches {len(r.seen)}/64 squares from a1");
}

glob h = Hunt();

with entry {
    h spawn a1;
}

glob hr = h.reports;

with entry {
    print(f"king walk found h8: {h.found == 1}, after visiting {len(hr)} squares");
}
