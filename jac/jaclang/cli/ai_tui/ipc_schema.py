# Canonical IPC wire protocol — single source of truth for field names and
# command tokens.  The Jac mirror is ../ai_tui_na/ipc_schema.na.jac; every
# string value here MUST match the corresponding glob there.

# host → TUI frame fields
FIELD_TYPE = "TYPE"
FIELD_STATUS = "STATUS"
FIELD_ACTIVE = "ACTIVE"
FIELD_MODEL = "MODEL"
FIELD_NEEDS_KEY = "NEEDS_KEY"
FIELD_KEY_ENV = "KEY_ENV"
FIELD_EV = "EV"
FIELD_EVA = "EVA"
FIELD_LEN = "L"  # length-prefix line: L:<line-count>

# TYPE values
FTYPE_FULL = "full"
FTYPE_DELTA = "delta"
FTYPE_HB = "hb"

# TUI → host command tokens
CMD_SEND = "SEND"  # SEND:<text>
CMD_STOP = "STOP"
CMD_RESET = "RESET"
CMD_QUIT = "QUIT"
CMD_APPLY = "APPLY"  # APPLY:key=val,key=val,...

FRAME_SEP = "---"
