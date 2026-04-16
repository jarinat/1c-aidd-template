# AIDD / Claude Code Template

Этот репозиторий предназначен для версионирования project-local комплекта
Claude Code и AIDD workflow для 1С/EDT/YAxUnit проектов. Цель — обновлять общий
процесс, agents, skills и core rules из одного шаблона, не полагаясь на
глобальный runtime в домашнем каталоге пользователя.

## Принятые решения

- Глобальный `~/.claude/CLAUDE.md` не используем.
- Agents, skills и core rules поставляем в каждый рабочий проект как
  project-local runtime bundle внутри `.claude`.
- Переносимость сохраняется на уровне содержания: `agents`, `skills` и
  `rules/core` не должны содержать конкретные project-specific детали.
- Project-specific слой остается в `.claude/rules/project` и
  `.claude/rules/paths` конкретного проекта.
- `aidd/docs` остается рабочей зоной тикетов конкретного проекта.
- Инструкции для Claude Code не храним в `aidd/docs/README.md`-файлах.
- `aidd/docs/feedback/README.md` не переносим как файл; его правила должны
  жить в skill/rule, например в `.claude/skills/aidd-fix-feedback/SKILL.md` и
  при необходимости в `.claude/rules/core/aidd-artifacts.md`.
- Локальные и машинозависимые настройки не версионируем.
- `~/.claude/settings.json` может оставаться локальной пользовательской
  настройкой машины, но не является частью этого шаблона.

## Целевая структура

```text
template/
  project/
    .claude/
      CLAUDE.md
      agents/
      rules/
        core/
        paths/
        project/
      scripts/
      skills/
    aidd/
      docs/
        adr/
        feedback/
        plan/
        prd/
        research/
        review/
        tasklist/

tools/
  check-shared.ps1
  sync-to-project.ps1
  sync-all-projects.ps1

config/
  projects.example.json
  projects.local.json   # не версионируется
```

`tools` и `config` в целевой структуре описывают планируемую инфраструктуру
синхронизации. Если файлов еще нет, это не означает, что архитектура должна
возвращаться к глобальному runtime в домашнем каталоге пользователя.

## Что хранится в `template/project/.claude`

`template/project/.claude` содержит полный комплект Claude Code инструкций,
который устанавливается в рабочий проект.

Подходит:

- `.claude/CLAUDE.md` как project entry point;
- переносимые agents;
- переносимые skills;
- переносимые core rules;
- шаблоны `.claude/rules/project/*`;
- шаблоны `.claude/rules/paths/*`;
- project entrypoint scripts из `.claude/scripts/*`, включая
  `commit-block.sh` и read-only helpers вроде `aidd-inspect.ps1`.

Не подходит:

- реальные PRD, plan, tasklist, research, feedback и review конкретных тикетов;
- secrets, credentials, локальные пути;
- `.claude/settings.local.json`;
- machine-specific permissions;
- project-specific детали внутри переносимых `agents`, `skills` и `rules/core`.

## Разделение слоев

Переносимый runtime-слой физически лежит в проекте, но остается общим по смыслу:

- `.claude/agents` — роли subagent-ов и границы ответственности;
- `.claude/skills` — исполняемые пошаговые сценарии;
- `.claude/rules/core` — общий AIDD workflow, review, git, code style и
  1С/EDT/YAxUnit правила.

Project-specific слой:

- `.claude/rules/project` — профиль проекта, тикеты, naming, testing,
  change policy и известные project pitfalls;
- `.claude/rules/paths` — правила для конкретных зон дерева;
- `.claude/scripts` — entrypoint scripts, которые вызываются по project-local
  путям и могут зависеть от project rules.

Если инструкция содержит конкретный проект, тикетный префикс, рабочий путь,
версию БСП или префикс метаданных, она не должна попадать в переносимые
`agents`, `skills` или `rules/core` без параметризации.

## Что остается в рабочем проекте

В каждом рабочем проекте остаются:

- `.claude/CLAUDE.md`;
- `.claude/agents/*`;
- `.claude/skills/*`;
- `.claude/rules/core/*`;
- `.claude/rules/project/*`;
- `.claude/rules/paths/*`;
- `.claude/scripts/*`;
- `aidd/docs/<type>/<ticket>.md`;
- `aidd/docs/.active_ticket`.

Если проекту позже понадобятся версионируемые project-level permissions,
`.claude/settings.json` можно добавить как project-specific файл. Локальные
разрешения пользователя и машины должны оставаться в `.claude/settings.local.json`
или `~/.claude/settings.json` и не попадать в этот шаблон.

## Правило для `.claude/scripts`

Если skill или agent вызывает скрипт по пути `.claude/scripts/<name>`, этот
скрипт должен поставляться через `template/project/.claude/scripts`.

Причина: `.claude/scripts/<name>` является путем внутри рабочего проекта.
Даже полностью переносимый helper должен быть установлен в проект, если
agents/skills обращаются к нему через `.claude/scripts/*`.

## Что не версионируем здесь

- `~/.claude/.credentials.json`;
- `~/.claude/.claude.json`;
- `~/.claude/projects`;
- `~/.claude/sessions`;
- `~/.claude/file-history`;
- `~/.claude/telemetry`;
- `~/.claude/cache`;
- `~/.claude/shell-snapshots`;
- `~/.claude/settings.json`;
- `.claude/settings.local.json`;
- `config/projects.local.json`;
- `aidd/tmp`;
- реальные тикетные артефакты из рабочих проектов.

## Правило добавления новых инструкций

Перед добавлением новой инструкции нужно выбрать слой:

- общее правило процесса: `template/project/.claude/rules/core`;
- исполняемый сценарий: `template/project/.claude/skills`;
- роль subagent: `template/project/.claude/agents`;
- проектное ограничение: `template/project/.claude/rules/project`;
- path-specific правило: `template/project/.claude/rules/paths`;
- project entrypoint script: `template/project/.claude/scripts`;
- состояние тикета: `aidd/docs/<type>/<ticket>.md` в рабочем проекте;
- локальное исключение пользователя или машины: не версионировать.

Если сомневаешься между `rules/core` и `rules/project`, выбирай по содержанию,
а не по физическому расположению. Общая методика — в `rules/core`; конкретика
проекта — в `rules/project` или `rules/paths`.

## Статус подготовки

Подготовлены для project-local runtime bundle:

- `agents/reviewer.md`: project-specific префикс заменен на ссылку на
  `.claude/rules/project/naming.md`.
- `skills/1c-query/SKILL.md`: проектные примеры заменены на нейтральные.
- `skills/yaxunit-tests/SKILL.md`: проектные примеры заменены на нейтральные.
- `skills/yaxunit-tests/references/api-reference.md`: проектные примеры
  заменены на нейтральные.
- `skills/aidd-commit-block/SKILL.md`: hardcode ticket prefix и default staged
  path заменены на project rules contract.
- `skills/1c-metadata-removal-impact/SKILL.md`: добавлена переносимая
  диагностика удаления элементов метаданных с gate для `USED` и `UNCLEAR`.

Подготовлены для `template/project/.claude/scripts`:

- `commit-block.sh`: убран универсальный default `src`; шаблон требует явный
  `--add-path` или проектную адаптацию безопасных default paths.
- `aidd-inspect.ps1`: проверен как read-only helper без project-specific
  маркеров.
- `scripts/README.md`: оставлен как описание project entrypoint scripts.

Подготовлены для `template/project`:

- `.claude/CLAUDE.md`: нейтральный project entry point, который ссылается на
  project-local `rules/core`, `skills`, `agents`, `rules/project`,
  `rules/paths` и `scripts`.
- `.claude/rules/project/*`: нейтральные шаблоны `profile`, `ticketing`,
  `naming`, `change-policy`, `testing`, `pitfalls`.
- `.claude/rules/paths/*`: README и нейтральный `source-example.md` без
  проектных путей.
- `aidd/docs/*/.gitkeep`: пустой каркас тикетных артефактов без
  `feedback/README.md`.

Осталось подготовить:

- `tools/check-shared.ps1`: автоматическая проверка переносимого runtime-слоя
  на случайную проектную специфику.
- `tools/sync-to-project.ps1`: установка `template/project` в один рабочий
  проект.
- `tools/sync-all-projects.ps1`: обновление проектов из локального списка.
- `config/projects.example.json`: пример локальной настройки списка проектов.

## Контроль переносимого слоя

Перед установкой или массовым обновлением нужно проверять, что в переносимом
runtime-слое нет случайной проектной специфики. Минимальный набор маркеров для
проверки:

```text
MPLSYS|INITKZ|PROSYS|Avtolid|Автолид|Intertop|src/cf_edt|ар_|INT_|Розница|Документооборот
```

Не каждое совпадение автоматически ошибка, но каждое должно быть осознанным и
обоснованным.
