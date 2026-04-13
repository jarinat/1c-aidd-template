# AIDD / Claude Code Template

Этот репозиторий предназначен для версионирования общей конфигурации Claude Code
и AIDD workflow, чтобы изменения в общем процессе не приходилось вручную
переносить между проектами.

## Принятые решения

- User-level `~/.claude/CLAUDE.md` не используем.
- Общий runtime-слой Claude Code храним в `~/.claude/rules`,
  `~/.claude/skills` и `~/.claude/agents`.
- Project-specific слой остается в `.claude` конкретного проекта.
- `aidd/docs` остается рабочей зоной тикетов конкретного проекта.
- Инструкции для Claude Code не храним в `aidd/docs/README.md`-файлах.
- `aidd/docs/feedback/README.md` не переносим как файл; его правила должны
  жить в общем skill/rule, например в `skills/aidd-fix-feedback/SKILL.md` и
  при необходимости в `rules/core/aidd-artifacts.md`.
- Project-specific правила не должны попадать в общие agents и skills.
- Локальные и машинозависимые настройки не версионируем.

## Целевая структура

```text
user/
  .claude/
    agents/
    rules/
      core/
    skills/

project-template/
  .claude/
    CLAUDE.md
    settings.json
    rules/
      paths/
      project/
    scripts/
  aidd/
    docs/
      feedback/
      plan/
      prd/
      research/
      review/
      tasklist/

tools/
  check-shared.ps1
  sync-to-project.ps1
  sync-to-user.ps1
```

## Что хранится в `user/.claude`

`user/.claude` содержит только переносимые правила и сценарии, которые могут
применяться в разных проектах.

Подходит:

- общие agents;
- общий AIDD workflow;
- общие rules `core`;
- общие skills;
- общие 1C/EDT/YAxUnit правила без привязки к проекту.

Не подходит:

- названия проектов;
- ticket prefixes вроде `MPLSYS` или `INITKZ`;
- конкретные рабочие пути вроде `src/cf_edt`;
- проектные префиксы метаданных вроде `ар_` или `INT_`;
- версии БСП и конфигураций;
- текущее состояние тикетов;
- локальные permissions и machine-specific настройки.

## Что хранится в `project-template`

`project-template` содержит каркас, который устанавливается в новый проект и
дорабатывается под него.

Подходит:

- минимальный `.claude/CLAUDE.md` как project entry point;
- пример `.claude/settings.json`;
- шаблоны `.claude/rules/project/*`;
- шаблоны `.claude/rules/paths/*`;
- проектный `scripts/commit-block.sh`, если он зависит от ticket format и
  default staged paths;
- пустая структура `aidd/docs/*`.

Не подходит:

- реальные PRD, plan, tasklist, research, feedback и review конкретных тикетов;
- `.claude/settings.local.json`;
- secrets, credentials, локальные пути.

## Что остается в проекте

В каждом рабочем проекте остаются:

- `.claude/CLAUDE.md`;
- `.claude/settings.json`;
- `.claude/rules/project/*`;
- `.claude/rules/paths/*`;
- `.claude/scripts/*`, если скрипт зависит от project rules;
- `aidd/docs/<type>/<ticket>.md`;
- `aidd/docs/.active_ticket`.

## Что не версионируем здесь

- `~/.claude/.credentials.json`;
- `~/.claude/.claude.json`;
- `~/.claude/projects`;
- `~/.claude/sessions`;
- `~/.claude/file-history`;
- `~/.claude/telemetry`;
- `~/.claude/cache`;
- `~/.claude/shell-snapshots`;
- `.claude/settings.local.json`;
- `aidd/tmp`;
- реальные тикетные артефакты из рабочих проектов.

## Правило добавления новых инструкций

Перед добавлением новой инструкции нужно выбрать слой:

- общее правило процесса: `user/.claude/rules/core`;
- исполняемый сценарий: `user/.claude/skills`;
- роль subagent: `user/.claude/agents`;
- проектное ограничение: `.claude/rules/project` в проекте;
- path-specific правило: `.claude/rules/paths` в проекте;
- состояние тикета: `aidd/docs/<type>/<ticket>.md` в проекте;
- локальное исключение пользователя или машины: не версионировать.

Если инструкция содержит конкретный проект, тикетный префикс, рабочий путь,
версию БСП или префикс метаданных, она не должна попадать в общий user-level
слой без параметризации.

## Файлы, требующие подготовки перед переносом

- `agents/reviewer.md`: убрать жесткий пример с `ар_`.
- `skills/1c-query/SKILL.md`: заменить проектные примеры на нейтральные.
- `skills/yaxunit-tests/SKILL.md`: заменить проектные примеры на нейтральные.
- `skills/yaxunit-tests/references/api-reference.md`: проверить примеры с
  проектными префиксами.
- `skills/aidd-commit-block/SKILL.md`: убрать hardcode ticket prefix,
  default staged path и commit subject format.
- `scripts/commit-block.sh`: параметризовать ticket prefix, subject format и
  default staged paths.
- `docs/claude-process-target-state.md`: убрать проектные маркеры и сделать
  документ общим.
- `settings.json`: разделить user-safe permissions и project permissions.

## Контроль shared-слоя

Перед установкой общего слоя нужно проверять, что в нем нет случайной проектной
специфики. Минимальный набор маркеров для проверки:

```text
MPLSYS|INITKZ|PROSYS|Avtolid|Автолид|Intertop|src/cf_edt|ар_|INT_|Розница|Документооборот
```

Не каждое совпадение автоматически ошибка, но каждое должно быть осознанным и
обоснованным.
