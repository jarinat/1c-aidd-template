# Tool usage policy

Выбор инструмента задан корпоративным стандартом
[`agent-tools.md`](../../../doc/ai/standards/agent-tools.md) и здесь не
повторяется: самый узкий подходящий инструмент; перечень операций, для которых
оболочка не используется (проверка существования файла, чтение файла или
диапазона строк, нарезка перед правкой, дамп байтов, проверка BOM и кодировки,
обход не-ASCII путей); правила путей в Bash на Windows; discovery перед content
для MCP и предусловие среды EDT MCP; один активный механизм записи; безопасное
редактирование через инструментарий EDT; политика «когда fallback допустим без
решения человека»; требования к записи о пробеле и к наблюдениям об MCP-сервере.

Здесь только AIDD-дельта: какие источники истины подставляются в эти правила и
куда в этом процессе записывается пробел.

## Источники, специфичные для этого слоя

- AIDD-артефакты активного тикета читай по протоколу из
  `.claude/rules/core/aidd-artifacts.md`: точные repo-relative пути через
  `Read`, `Glob` только при неизвестном ticket id. Оболочка для проверки их
  наличия не используется — это частный случай общего запрета из стандарта.
- Единственный EDT MCP берётся из project-local `.mcp.json`, и ему соответствует
  ровно один skill: `edt-companion-mcp` → `mpl-edt-companion-mcp`,
  `edt-mcp` → `mpl-edt-mcp`, `1c-rsv` → `mpl-1c-rsv`. Другой EDT MCP не является
  fallback ни при недоступности, ни при непокрытой операции.
- Runtime-диагностика живой базы — `.claude/skills/1c-debug-info-tools/SKILL.md`,
  если MCP `1c-debug-info` доступен.
- Сложная повторяемая диагностика — project-local helper из `.claude/scripts/*`,
  предпочтительно `.cmd` wrapper на Windows, а не inline-команда оболочки.
- Git status, diff, log и commit helpers — по
  `.claude/rules/core/git-workflow.md` и `.claude/skills/aidd-commit-block/SKILL.md`.

## Куда записывать Tooling gap

Содержание записи задано стандартом. Место записи зависит от текущего сценария:

- `implement` — в `tasklist` текущего блока при его обновлении;
- `fast-implement` — в PRD, раздел `Implementation notes / Tooling gaps`, без
  изменения требований, статуса, решений и acceptance criteria;
- `feedback-fix` — в соответствующей записи `FB-XXX`;
- `debug-loop` — в текущей итерации `aidd/docs/debug/<ticket>.md`;
- `review-fix` — в соответствующей записи `RV-XXX`;
- review и research — как наблюдение в соответствующем артефакте, если пробел
  влияет на полноту проверки.

Каноническим местом для наблюдений об EDT MCP является `research` текущего
тикета, а при его отсутствии — PRD, раздел
`Implementation notes / Tooling observations / EDT MCP`. Не дублируй полный текст
между артефактами: на позднем этапе допустима краткая запись в текущем
stage-артефакте со ссылкой на канонический.

## Hook

`.claude/settings.json` содержит `PreToolUse` guard для `Bash`, который
блокирует inline shell file inspection. Если hook вернул отказ, перестрой
действие по стандарту, а не проси пользователя разрешить заблокированную
команду.
