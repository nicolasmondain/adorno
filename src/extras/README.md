# Extras per tool

Tool-specific files, copied as-is into the project by `kit install`.
The path under `src/extras/<target>/` is the final path in the project.

```
src/extras/claude/.claude/settings.json      # permissions, Claude Code hooks
src/extras/claude/.mcp.json                  # the project's MCP servers
src/extras/gemini/.gemini/settings.json
src/extras/claude-plugin/hooks/hooks.json    # hooks bundled in the Claude Code plugin
src/extras/claude-plugin/.mcp.json           # MCP servers bundled in the plugin
```

This README is not copied anywhere: only the folders whose name is a target
(`claude`, `codex`, `gemini`, `copilot`, `cursor`) or `claude-plugin` are read.
