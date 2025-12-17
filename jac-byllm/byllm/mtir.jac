"""MTRuntime (Meaning Typed Intermediate Representation) module for JacLang runtime library."""
import inspect;
import json;
import from types { MethodType }
import from typing { Callable, get_type_hints }
import from byllm.schema { json_to_instance, type_to_schema }
import from byllm.types {
    LiteLLMMessage,
    Media,
    Message,
    MessageRole,
    MessageType,
    Text,
    Tool
}

"""A class representing the MTIR for JacLang."""
obj MTIR {
    has caller: Callable;
    has args: dict[int | str, object];
    has call_params: dict[str, object];

    @property
    def runtime()  -> MTRuntime {
        return MTRuntime.factory(self.caller, self.args, self.call_params);
    }
}

"""A class representing the MTRuntime for JacLang."""
obj MTRuntime {
    has messages: list[MessageType];
    has resp_type: type | None;
    has stream: bool;
    has tools: list[Tool];
    has call_params: dict[str, object];

    # FIXME: Comeup with a better name
    """Create an MTRuntime instance."""
    static def factory(
        caller: Callable, args: dict[int | str, object], call_params: dict[str, object]
    ) -> MTRuntime;

    """Dispatch the parameters for the MTRuntime."""
    def dispatch_params()  -> dict[str, object];

    """Add a message to the request."""
    def add_message(message: MessageType) -> None;

    """Return the messages in a format suitable for LLM API."""
    def get_msg_list()  -> list[dict[str, object] | LiteLLMMessage];

    """Parse the response from the LLM."""
    def parse_response(response: str) -> object;

    """Get a tool by its name."""
    def get_tool(tool_name: str) -> Tool | None;

    """Return the tools in a format suitable for LLM API."""
    def get_tool_list()  -> list[dict];

    """Return the JSON schema for the response type."""
    def get_output_schema()  -> dict | None;
}
