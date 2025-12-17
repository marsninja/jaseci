"""LLM abstraction module.

This module provides a LLM class that abstracts LiteLLM and offers
enhanced functionality and interface for language model operations.
"""

import logging;
import from loguru { logger }
import os;
import sys;
import json;
import random;
import time;

import from typing { Generator }
import from byllm.mtir { MTRuntime }
import litellm;
import from litellm._logging { _disable_debugging }
import from openai { OpenAI }
import from byllm.types {
    CompletionResult,
    LiteLLMMessage,
    MockToolCall,
    ToolCall,
    Message,
    MessageRole
}
# This will prevent LiteLLM from fetching pricing information from
# the bellow URL every time we import the litellm and use a cached
# local json file. Maybe we we should conditionally enable this.
# https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json
with entry {
    os.environ["LITELLM_LOCAL_MODEL_COST_MAP"] = "True";
}

glob DEFAULT_BASE_URL = "http://localhost:4000";
glob MODEL_MOCK = "mockllm";

glob SYSTEM_PERSONA = """\
This is a task you must complete by returning only the output.
Do not include explanations, code, or extra text—only the result.
""";  # noqa E501


glob INSTRUCTION_TOOL = """
Use the tools provided to reach the goal. Call one tool at a time with \
proper args—no explanations, no narration. Think step by step, invoking tools \
as needed. When done, always call finish_tool(output) to return the final \
output. Only use tools.
""";  # noqa E501


"""Base class for LLM implementations.

Provides the core interface and shared functionality for all LLM connectors.
Subclasses must implement model_call_no_stream and model_call_with_stream
to define how the actual LLM API is called.
"""
obj BaseLLM {
    def init(model_name: str, **kwargs: object) -> None;
    def __call__( **kwargs: object)  -> BaseLLM;
    def invoke(mtir: MTRuntime) -> object;
    def make_model_params(mtir: MTRuntime) -> dict;
    def log_info(message: str) -> None;
    def format_prompt(params: dict) -> str;
    def dispatch_no_streaming(mtir: MTRuntime) -> CompletionResult;
    def dispatch_streaming(mtir: MTRuntime) -> Generator[str, None, None];
    def model_call_no_stream(params: dict) -> dict;
    def model_call_with_stream(params: dict) -> Generator[str, None, None];
    def _stream_final_answer(mtir: MTRuntime) -> Generator[str, None, None];
}

"""Mock LLM connector that simulates responses for testing.

Useful for unit testing and development without making real API calls.
Configure outputs via the 'outputs' kwarg to control mock responses.
"""
obj MockLLM(BaseLLM) {
    def init(model_name: str, **kwargs: object) -> None;
    override def dispatch_no_streaming(mtir: MTRuntime) -> CompletionResult;
    override def dispatch_streaming(mtir: MTRuntime) -> Generator[str, None, None];
}

"""Primary LLM connector that abstracts LiteLLM functionality.

Provides a unified interface for interacting with various language models
(OpenAI, Anthropic, etc.) through LiteLLM. Supports both direct API calls
and proxy-based routing. Automatically delegates to MockLLM when model_name
is 'mockllm'.
"""
obj Model(BaseLLM) {
    def init(model_name: str, **kwargs: object) -> None;
    override def invoke(mtir: MTRuntime) -> object;
    def model_call_no_stream(params: dict) -> dict;
    def model_call_with_stream(params: dict);
}
