# Claude Hooks

Этот каталог содержит project-level hooks для Claude Code.

Hooks здесь являются частью переносимого runtime-слоя шаблона и должны быть
детерминированными guard-ами без secrets, machine-specific путей и локальных
permission rules.

## Hooks

- `block-inline-file-inspection.ps1` -- `PreToolUse` guard для `Bash`,
  `Read`/`Write`/`Edit`/`Glob`/`Grep` и MCP 1С/EDT (`edt-mcp`, `1c-rsv`), который блокирует
  опасные обходы штатных инструментов и возвращает агенту подсказку
  использовать `.claude/rules/core/tool-usage.md`, профильный skill или
  documented helper.

## Правила

- На Windows подключай PowerShell hook напрямую через `"shell": "powershell"` и
  repo-relative путь к `.ps1`. Не добавляй `cmd /c call` и не используй
  `%CLAUDE_PROJECT_DIR%` в hook command: Claude Code запускает hook command
  через shell, где cmd-переменные могут не разворачиваться.
- Не добавляй сюда локальные разрешения, токены, пути к машине пользователя или
  project-specific команды.
- Локальные настройки должны жить в `.claude/settings.local.json` или
  `~/.claude/settings.json`.
- Если hook запрещает действие, причина должна объяснять агенту, какой
  штатный инструмент или documented helper использовать вместо blocked command.
