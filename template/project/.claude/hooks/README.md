# Claude Hooks

Этот каталог содержит project-level hooks для Claude Code.

Hooks здесь являются частью переносимого runtime-слоя шаблона и должны быть
детерминированными guard-ами без secrets, machine-specific путей и локальных
permission rules.

## Hooks

- `block-inline-file-inspection.cmd` -- Windows-friendly entrypoint для hook.
- `block-inline-file-inspection.ps1` -- `PreToolUse` guard для `Bash`, который
  блокирует inline shell-команды для file inspection и возвращает агенту
  подсказку использовать `.claude/rules/core/tool-usage.md`.

## Правила

- Не добавляй сюда локальные разрешения, токены, пути к машине пользователя или
  project-specific команды.
- Локальные настройки должны жить в `.claude/settings.local.json` или
  `~/.claude/settings.json`.
- Если hook запрещает действие, причина должна объяснять агенту, какой
  штатный инструмент или documented helper использовать вместо blocked command.
