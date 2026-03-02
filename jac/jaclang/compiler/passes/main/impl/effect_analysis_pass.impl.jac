"""Effect Analysis Pass implementation."""
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.passes { UniPass }
import from jaclang.jac0core.constant { SymbolType }
import from jaclang.jac0core.constant { Tokens as Tok }
import from typing { Any }

impl EffectAnalysisPass.init(
    ir_in: uni.Module, prog: Any, cancel_token: Any = None
) -> None {
    super.init(ir_in, prog, cancel_token);
}

"""Scan a list of body statements for side effects.

Returns {"is_writer": bool, "touches": list[str]} where touches
contains the names of node/edge types affected.
"""
impl EffectAnalysisPass._scan_effects(body_nodes: list) -> dict {
    is_writer = False;
    touches: set[str] = set();

    # Walk descendants manually since body_nodes is a list not a node
    def walk(nodes: list) -> None {
        nonlocal is_writer ;
        for nd in nodes {
            if not isinstance(nd, uni.UniNode) {
                continue;
            }
            # Edge creation
            if isinstance(nd, uni.BinaryExpr) and isinstance(nd.op, uni.ConnectOp) {
                is_writer = True;
                if nd.op?.conn_type and nd.op.conn_type {
                    if hasattr(nd.op.conn_type, 'sym_name') {
                        touches.add(nd.op.conn_type.sym_name);
                    }
                }
            }
            # Edge deletion
            elif isinstance(nd, uni.BinaryExpr)
            and isinstance(nd.op, uni.DisconnectOp) {
                is_writer = True;
            }
            # Node/edge deletion
            elif isinstance(nd, uni.DeleteStmt) {
                is_writer = True;
            }
            # Spawn
            elif isinstance(nd, uni.BinaryExpr) {
                if nd.op?.name and nd.op.name == Tok.KW_SPAWN {
                    is_writer = True;
                }
            }
            # Field mutation on non-self
            elif isinstance(nd, uni.Assignment) {
                if nd.target and len(nd.target) > 0 {
                    tgt = nd.target[0];
                    if isinstance(tgt, uni.AtomTrailer) and tgt.is_attr {
                        if tgt.target and isinstance(tgt.target, uni.Name) {
                            if tgt.target.value != "self" {
                                is_writer = True;
                            }
                        }
                    }
                }
            }
            # Archetype instantiation (node/edge construction)
            elif isinstance(nd, uni.FuncCall) {
                if isinstance(nd.target, uni.Name)
                and nd.target?.sym
                and nd.target.sym {
                    if nd.target.sym.sym_type in [
                        SymbolType.NODE_ARCH,
                        SymbolType.EDGE_ARCH
                    ] {
                        touches.add(nd.target.sym_name);
                        is_writer = True;
                    }
                }
            }
            # Event signatures
            elif isinstance(nd, uni.EventSignature) {
                if nd?.arch_tag_info and nd.arch_tag_info {
                    if isinstance(nd.arch_tag_info, uni.Expr) {
                        if isinstance(nd.arch_tag_info, uni.Name) {
                            touches.add(nd.arch_tag_info.value);
                        }
                    }
                }
            }
            # Recurse into children
            if nd?.kid and nd.kid {
                walk(list(nd.kid));
            }
        }
    }

    walk(body_nodes);
    return {"is_writer": is_writer, "touches": sorted(touches) if touches else ["*"]};
}

"""Analyze ability body for side effects."""
impl EffectAnalysisPass.exit_ability(nd: uni.Ability) -> None {
    if nd.body and isinstance(nd.body, list) and len(nd.body) > 0 {
        nd.gen.body_effects = self._scan_effects(list(nd.body));
    }
}

"""Analyze module code (entry block) for side effects."""
impl EffectAnalysisPass.exit_module_code(nd: uni.ModuleCode) -> None {
    if nd.body and isinstance(nd.body, list) and len(nd.body) > 0 {
        nd.gen.body_effects = self._scan_effects(list(nd.body));
    }
}

"""Analyze archetype (walker/node/edge) resolved body for side effects."""
impl EffectAnalysisPass.exit_archetype(nd: uni.Archetype) -> None {
    resolved_body = nd._get_impl_resolved_body();
    if resolved_body and isinstance(resolved_body, list) and len(resolved_body) > 0 {
        nd.gen.body_effects = self._scan_effects(list(resolved_body));
    }
}
