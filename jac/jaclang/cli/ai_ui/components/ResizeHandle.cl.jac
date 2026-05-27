"""A draggable gutter that reports pointer-movement deltas to its parent.

`vertical` sits between side-by-side panes and reports horizontal deltas (drag
left/right); otherwise it sits between stacked panes and reports vertical deltas
(drag up/down). The parent applies the delta to a pane size it holds in state, so
this component owns the drag mechanics and stays layout-agnostic.

Listeners are attached to `window` on mousedown and removed on mouseup, so a drag
keeps tracking even when the pointer moves faster than the 6px gutter.
"""

def:pub ResizeHandle(vertical: bool, onResize: any) -> JsxElement {
    def onDown(e: any) {
        e.preventDefault();
        def onMove(ev: any) {
            onResize(ev.movementX if vertical else ev.movementY);
        }
        def onUp(ev: any) {
            window.removeEventListener("mousemove", onMove);
            window.removeEventListener("mouseup", onUp);
            document.body.classList.remove("resizing");
        }
        # While dragging, suppress text selection / cursor flicker across the page.
        document.body.classList.add("resizing");
        window.addEventListener("mousemove", onMove);
        window.addEventListener("mouseup", onUp);
    }
    return
        <div
            className={"resize-handle " + ("v" if vertical else "h")}
            onMouseDown={onDown}
        />;
}
