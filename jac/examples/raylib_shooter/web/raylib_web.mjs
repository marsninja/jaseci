// raylib_web.mjs - a minimal WebGL shim for the scalar rlgl immediate-mode API
// used by shooter.na.jac. It provides exactly the `env` imports the wasm module
// declares (the `import from raylib { ... }` block becomes wasm imports), plus
// the tiny libc/runtime surface the Jac native runtime references.
//
// rlgl is OpenGL-immediate-mode in spirit: rlBegin/rlVertex3f/rlColor4ub batches,
// a projection+modelview matrix stack, push/pop, translate/rotate, frustum/ortho.
// We emulate that on a single WebGL pipeline (one VBO, one MVP shader).

// ── 4x4 column-major matrix helpers ─────────────────────────────────────────
const ident = () => [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1];
function mul(a, b) {            // a * b  (column-major)
  const c = new Array(16).fill(0);
  for (let col = 0; col < 4; col++)
    for (let row = 0; row < 4; row++) {
      let s = 0;
      for (let k = 0; k < 4; k++) s += a[row + 4*k] * b[k + 4*col];
      c[row + 4*col] = s;
    }
  return c;
}
function translate(x, y, z) { const m = ident(); m[12]=x; m[13]=y; m[14]=z; return m; }
function rotate(angDeg, x, y, z) {
  const a = angDeg * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
  let len = Math.hypot(x, y, z) || 1; x/=len; y/=len; z/=len; const t = 1 - c;
  return [
    x*x*t+c,   y*x*t+z*s, x*z*t-y*s, 0,
    x*y*t-z*s, y*y*t+c,   y*z*t+x*s, 0,
    x*z*t+y*s, y*z*t-x*s, z*z*t+c,   0,
    0,0,0,1,
  ];
}
function frustum(l, r, b, t, n, f) {
  return [
    2*n/(r-l), 0, 0, 0,
    0, 2*n/(t-b), 0, 0,
    (r+l)/(r-l), (t+b)/(t-b), -(f+n)/(f-n), -1,
    0, 0, -2*f*n/(f-n), 0,
  ];
}
function ortho(l, r, b, t, n, f) {
  return [
    2/(r-l), 0, 0, 0,
    0, 2/(t-b), 0, 0,
    0, 0, -2/(f-n), 0,
    -(r+l)/(r-l), -(t+b)/(t-b), -(f+n)/(f-n), 1,
  ];
}

// raylib key codes the shooter reads → from JS KeyboardEvent.code
const KEYMAP = {
  KeyW: 87, KeyA: 65, KeyS: 83, KeyD: 68, Space: 32, Tab: 258,
  ArrowRight: 262, ArrowLeft: 263, ArrowDown: 264, ArrowUp: 265,
};
const RL_LINES = 1, RL_TRIANGLES = 4, RL_PROJECTION = 0x1701;

// Build the wasm `env` import object plus per-frame hooks.
//   onScore(n): optional HUD callback invoked each frame with get_score-like value
export function makeEnv({ canvas, onFps } = {}) {
  const gl = canvas.getContext("webgl", { antialias: true, depth: true });
  if (!gl) throw new Error("WebGL not available");

  // one shader: position + color, MVP uniform
  const vs = `attribute vec3 aPos; attribute vec4 aCol; uniform mat4 uMVP;
    varying vec4 vCol; void main(){ gl_Position = uMVP * vec4(aPos,1.0); vCol = aCol; }`;
  const fs = `precision mediump float; varying vec4 vCol;
    void main(){ gl_FragColor = vCol; }`;
  const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s; };
  const prog = gl.createProgram();
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, vs));
  gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, fs));
  gl.linkProgram(prog); gl.useProgram(prog);
  const aPos = gl.getAttribLocation(prog, "aPos");
  const aCol = gl.getAttribLocation(prog, "aCol");
  const uMVP = gl.getUniformLocation(prog, "uMVP");
  const vbo = gl.createBuffer();
  gl.clearColor(0, 0, 0, 1);
  gl.disable(gl.CULL_FACE);            // depth test alone resolves the cube faces

  // matrix stacks + immediate-mode batch state
  let proj = ident(), mv = ident(), mode = 0;
  const projStack = [], mvStack = [];
  const cur = () => (mode === RL_PROJECTION ? proj : mv);
  const setCur = (m) => { if (mode === RL_PROJECTION) proj = m; else mv = m; };
  let batchMode = 0, verts = [], color = [1, 1, 1, 1];

  // shared mutable state (filled by attach() after instantiate)
  const st = { mem: null, heap: 0, dt: 0.016, time: 0,
               mouseX: 0, mouseY: 0, locked: false };
  const keysDown = new Set(), keysPressed = new Set(), mousePressed = new Set();
  const u8 = () => new Uint8Array(st.mem.buffer);
  const cstr = (p) => { const m = u8(); let s = ""; while (m[p]) s += String.fromCharCode(m[p++]); return s; };

  // ── input listeners ──
  addEventListener("keydown", (e) => {
    const k = KEYMAP[e.code]; if (k === undefined) return; e.preventDefault();
    if (!keysDown.has(k)) keysPressed.add(k);
    keysDown.add(k);
  });
  addEventListener("keyup", (e) => { const k = KEYMAP[e.code]; if (k !== undefined) keysDown.delete(k); });
  canvas.addEventListener("mousedown", () => mousePressed.add(0));
  document.addEventListener("mousemove", (e) => {
    if (st.locked) { st.mouseX += e.movementX; st.mouseY += e.movementY; }
    else { st.mouseX = e.offsetX | 0; st.mouseY = e.offsetY | 0; }
  });
  document.addEventListener("pointerlockchange", () => { st.locked = document.pointerLockElement === canvas; });

  function flush() {                   // rlEnd: draw the accumulated batch
    if (!verts.length) return;
    const mvp = mul(proj, mv);
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(verts), gl.STREAM_DRAW);
    const stride = 7 * 4;
    gl.enableVertexAttribArray(aPos); gl.vertexAttribPointer(aPos, 3, gl.FLOAT, false, stride, 0);
    gl.enableVertexAttribArray(aCol); gl.vertexAttribPointer(aCol, 4, gl.FLOAT, false, stride, 3 * 4);
    gl.uniformMatrix4fv(uMVP, false, new Float32Array(mvp));
    gl.drawArrays(batchMode === RL_LINES ? gl.LINES : gl.TRIANGLES, 0, verts.length / 7);
    verts = [];
  }

  const env = {
    // ── window / lifecycle ──
    InitWindow: (w, h, titlePtr) => { document.title = cstr(titlePtr) + " - Jac/WASM"; },
    WindowShouldClose: () => 0, CloseWindow: () => {}, SetTargetFPS: () => {},
    BeginDrawing: () => { gl.viewport(0, 0, canvas.width, canvas.height); },
    EndDrawing: () => {}, EndMode3D: () => { flush(); },
    GetFrameTime: () => st.dt, GetTime: () => st.time,
    DrawFPS: () => { if (onFps) onFps(Math.round(1 / Math.max(st.dt, 1e-4))); },

    // ── input ──
    IsKeyDown: (k) => (keysDown.has(k) ? 1 : 0),
    IsKeyPressed: (k) => (keysPressed.has(k) ? 1 : 0),
    GetMouseX: () => st.mouseX, GetMouseY: () => st.mouseY,
    IsMouseButtonPressed: (b) => (mousePressed.has(b) ? 1 : 0),
    DisableCursor: () => { canvas.requestPointerLock && canvas.requestPointerLock(); },
    EnableCursor: () => { document.exitPointerLock && document.exitPointerLock(); },

    // ── rlgl immediate mode ──
    rlClearColor: (r, g, b, a) => gl.clearColor(r/255, g/255, b/255, a/255),
    rlClearScreenBuffers: () => gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT),
    rlEnableDepthTest: () => gl.enable(gl.DEPTH_TEST),
    rlDisableDepthTest: () => gl.disable(gl.DEPTH_TEST),
    rlMatrixMode: (m) => { mode = m; },
    rlLoadIdentity: () => setCur(ident()),
    rlPushMatrix: () => { if (mode === RL_PROJECTION) projStack.push(proj.slice()); else mvStack.push(mv.slice()); },
    rlPopMatrix: () => { if (mode === RL_PROJECTION) proj = projStack.pop(); else mv = mvStack.pop(); },
    rlTranslatef: (x, y, z) => setCur(mul(cur(), translate(x, y, z))),
    rlRotatef: (a, x, y, z) => setCur(mul(cur(), rotate(a, x, y, z))),
    rlFrustum: (l, r, b, t, n, f) => setCur(mul(cur(), frustum(l, r, b, t, n, f))),
    rlOrtho: (l, r, b, t, n, f) => setCur(mul(cur(), ortho(l, r, b, t, n, f))),
    rlBegin: (m) => { batchMode = m; verts = []; },
    rlEnd: () => flush(),
    rlVertex3f: (x, y, z) => { verts.push(x, y, z, color[0], color[1], color[2], color[3]); },
    rlColor4ub: (r, g, b, a) => { color = [r/255, g/255, b/255, a/255]; },
    rlSetLineWidth: (w) => gl.lineWidth(w),

    // ── raylib file helpers (benchmark path; dormant in interactive play) ──
    FileExists: () => 0, LoadFileText: () => 0, TextToInteger: () => 0, SaveFileText: () => 0,

    // ── libc / Jac native runtime surface ──
    malloc: (n) => { n = Number(n); const p = st.heap; st.heap = (st.heap + n + 7) & ~7; return p; },
    calloc: (c, s) => { const n = Number(c) * Number(s); const p = st.heap; st.heap = (st.heap + n + 7) & ~7;
                        u8().fill(0, p, p + n); return p; },
    free: () => {}, malloc_usable_size: () => 0,
    memcpy: (d, s, n) => { u8().copyWithin(d, s, s + Number(n)); return d; },
    memcmp: (a, b, n) => { const m = u8(); n = Number(n);
      for (let i = 0; i < n; i++) { const d = m[a+i] - m[b+i]; if (d) return d; } return 0; },
    puts: () => 0, printf: () => 0, snprintf: () => 0, getenv: () => 0, fflush: () => 0,
    abort: () => { throw new Error("wasm abort()"); },
    // 128-bit multiply (overflow-checked int math); write the 16-byte result to *res.
    __multi3: (res, alo, ahi, blo, bhi) => {
      const M = (1n << 64n) - 1n;
      const a = (BigInt.asUintN(64, ahi) << 64n) | BigInt.asUintN(64, alo);
      const b = (BigInt.asUintN(64, bhi) << 64n) | BigInt.asUintN(64, blo);
      const p = BigInt.asUintN(128, a * b), dv = new DataView(st.mem.buffer);
      dv.setBigUint64(res, p & M, true); dv.setBigUint64(res + 8, (p >> 64n) & M, true);
    },
  };

  return {
    env,
    // wire memory + heap after instantiate
    attach(exports) { st.mem = exports.memory; st.heap = exports.__heap_base.value; },
    // call at the start of each rAF tick with the high-res timestamp (ms)
    beginTick(tsMs) {
      if (!st._t0) st._t0 = tsMs;
      const now = (tsMs - st._t0) / 1000;
      st.dt = st.time ? Math.min(now - st.time, 0.05) : 0.016;
      st.time = now;
    },
    // clear per-frame edge state after frame()
    endTick() { keysPressed.clear(); mousePressed.clear(); },
  };
}
