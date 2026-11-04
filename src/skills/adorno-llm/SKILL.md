---
name: adorno-llm
description: Send a well-delimited task (triage, routing, a review of a given diff…) to another model through any OpenAI-compatible endpoint - OpenRouter, OpenAI, Google, your own models - and get the answer back as JSON. Used by agents that the owner routed to an external model (models.agents.<id>.route in their personal layer); also usable by hand for a cheap one-shot task.
---

# adorno-llm

`scripts/llm-run` (relative to this file) sends **one** prompt to a chat endpoint compatible with the OpenAI API and
prints `{route, model, content, finish_reason, usage}`. It holds no conversation and runs no tools: the host agent
gathers the inputs with its own tools, sends them, then checks the answer.

```sh
scripts/llm-run --base-url https://openrouter.ai/api/v1 --model qwen/qwen3-coder --key-env OPENROUTER_API_KEY \
  --system role.md prompt.md > reply.json
```

| Option | |
| --- | --- |
| `--base-url` | the endpoint's base (`…/v1`); https only, or localhost for a local model |
| `--model` | the provider's model id |
| `--key-env` | the **name** of the variable holding the key (default `OPENROUTER_API_KEY`); the key itself never appears in a file or a command line |
| `--system FILE` | the role's instructions |
| `--max-tokens`, `--temperature`, `--timeout` | optional |

`LLM_RUN_DRY_RUN=1` prints the request without sending it. Exit codes: 2 usage, 3 key missing, 4 refused URL, 6 the
endpoint failed.

## Rules

- **Nothing secret or personal leaves**: no key, token, password, customer data or raw log line with personal data in
  a prompt. Reduce or drop such an input, and say so.
- A repo with `models.external: false` in the owner's settings never sends anything out: do the task in the host.
- The answer is a **candidate**: check its format and every `file:line` it cites before using it. One retry with the
  error; a second failure or an unavailable endpoint → do the task in the host and report it.
- Report `model` and `usage` (tokens) in the run's report, so the owner sees what each route costs.
