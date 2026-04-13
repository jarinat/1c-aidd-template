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
template/
  user/
    .claude/
      agents/
      rules/
        core/
      skills/

  project/
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

## Что хранится в `template/user/.claude`

`template/user/.claude` содержит только переносимые правила и сценарии, которые
могут применяться в разных проектах.

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
- project entrypoint scripts, которые вызываются как `.claude/scripts/*`;
- локальные permissions и machine-specific настройки.

## Что хранится в `template/project`

`template/project` содержит каркас, который устанавливается в новый проект и
дорабатывается под него.

Подходит:

- минимальный `.claude/CLAUDE.md` как project entry point;
- пример `.claude/settings.json`;
- шаблоны `.claude/rules/project/*`;
- шаблоны `.claude/rules/paths/*`;
- project entrypoint scripts из `.claude/scripts/*`, включая
  `commit-block.sh` и read-only helpers вроде `aidd-inspect.ps1`;
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

## Правило для `.claude/scripts`

Если skill или agent вызывает скрипт по пути `.claude/scripts/<name>`, этот
скрипт должен поставляться через `template/project/.claude/scripts`, а не через
`template/user/.claude/scripts`.

Причина: `.claude/scripts/<name>` является путем внутри рабочего проекта. Общий
user-level skill может ссылаться на такой entrypoint, но сам entrypoint должен
быть установлен в проект и при необходимости адаптирован под project rules.

Полностью переносимые helper-скрипты тоже могут лежать в `template/project`,
если agents/skills обращаются к ним через `.claude/scripts/*`. User-level
scripts допустимы только если все ссылки используют user-level путь явно.

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

- общее правило процесса: `template/user/.claude/rules/core`;
- исполняемый сценарий: `template/user/.claude/skills`;
- роль subagent: `template/user/.claude/agents`;
- проектное ограничение: `.claude/rules/project` в проекте;
- path-specific правило: `.claude/rules/paths` в проекте;
- project entrypoint script: `template/project/.claude/scripts`;
- состояние тикета: `aidd/docs/<type>/<ticket>.md` в проекте;
- локальное исключение пользователя или машины: не версионировать.

Если инструкция содержит конкретный проект, тикетный префикс, рабочий путь,
версию БСП или префикс метаданных, она не должна попадать в общий user-level
слой без параметризации.

## Статус подготовки

Подготовлены для общего `template/user/.claude`:

- `agents/reviewer.md`: project-specific префикс заменен на ссылку на
  `.claude/rules/project/naming.md`.
- `skills/1c-query/SKILL.md`: проектные примеры заменены на нейтральные.
- `skills/yaxunit-tests/SKILL.md`: проектные примеры заменены на нейтральные.
- `skills/yaxunit-tests/references/api-reference.md`: проектные примеры
  заменены на нейтральные.
- `skills/aidd-commit-block/SKILL.md`: hardcode ticket prefix и default staged
  path заменены на project rules contract.

Подготовлены для `template/project/.claude/scripts`:

- `commit-block.sh`: убран универсальный default `src`; шаблон требует явный
  `--add-path` или проектную адаптацию безопасных default paths.
- `aidd-inspect.ps1`: проверен как read-only helper без project-specific
  маркеров.
- `scripts/README.md`: оставлен как описание project entrypoint scripts.

Осталось подготовить:

- `docs/claude-process-target-state.md`: убрать проектные маркеры и сделать
  документ общим, если решим переносить этот документ.
- `settings.json`: разделить user-safe permissions и project permissions.

## Контроль shared-слоя

Перед установкой общего слоя нужно проверять, что в нем нет случайной проектной
специфики. Минимальный набор маркеров для проверки:

```text
MPLSYS|INITKZ|PROSYS|Avtolid|Автолид|Intertop|src/cf_edt|ар_|INT_|Розница|Документооборот
```

Не каждое совпадение автоматически ошибка, но каждое должно быть осознанным и
обоснованным.
