# Extras par outil

Fichiers propres à un outil, copiés tels quels dans le projet par `kit install`.
Le chemin sous `src/extras/<cible>/` est le chemin final dans le projet.

```
src/extras/claude/.claude/settings.json      # permissions, hooks Claude Code
src/extras/claude/.mcp.json                  # serveurs MCP du projet
src/extras/gemini/.gemini/settings.json
src/extras/claude-plugin/hooks/hooks.json    # hooks embarqués dans le plugin Claude Code
src/extras/claude-plugin/.mcp.json           # MCP embarqués dans le plugin
```

Ce README n'est copié nulle part : seuls les dossiers dont le nom est une cible
(`claude`, `codex`, `gemini`, `copilot`, `cursor`) ou `claude-plugin` sont lus.
