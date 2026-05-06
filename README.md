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
- `.claude/settings.json` в шаблоне допускается только для переносимых
  deterministic hooks без secrets, machine-specific путей и локальных
  permission rules.

## Целевая структура

```text
template/
  project/
    .claude/
      CLAUDE.md
      settings.json
      agents/
      docs/
      hooks/
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
  bootstrap-project.ps1
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

## Быстрая локальная установка в проект

Для первичной подготовки проекта используй bootstrap-сценарий:

```powershell
tools/bootstrap-project.ps1 -Project WMS
tools/bootstrap-project.ps1 -Project WMS -Apply
```

`-Project` берется из локального `config/projects.local.json`. Если проекта нет
в списке, можно передать путь напрямую:

```powershell
tools/bootstrap-project.ps1 -ProjectPath C:/work/project -Apply
```

Bootstrap делает только локальную механическую подготовку:

- обновляет переносимый runtime-слой:
  `.claude/CLAUDE.md`, `.claude/settings.json`, `.claude/agents`,
  `.claude/hooks`, `.claude/skills`, `.claude/rules/core`,
  `.claude/scripts`, `.claude/docs`;
- создает отсутствующий локальный `AGENTS.md`;
- создает отсутствующие `.claude/rules/project/*`;
- создает базовые отсутствующие `.claude/rules/paths/*` без копирования
  placeholder-примера `source-example.md`;
- создает отсутствующий каркас `aidd/docs`.

Bootstrap не делает project onboarding за агента:

- не добавляет `.claude/`, `aidd/` или `AGENTS.md` в Git ignore/exclude;
- не запускает `rlm-bsl-index build/update`;
- не угадывает тикетные префиксы, naming policy, change policy и правила
  комментариев;
- не перезаписывает уже существующие project-specific rules.

После bootstrap проект нужно обследовать по сценарию:

```text
.claude/docs/onboarding-project.md
```

Для Claude Code есть skill `.claude/skills/project-onboarding/SKILL.md`. Для
Codex входом является локальный `AGENTS.md`, который ссылается на тот же общий
onboarding-документ.

## Локальный список проектов

`config/projects.example.json` содержит версионируемый пример списка проектов.
Реальный список ведется локально в `config/projects.local.json` и не попадает в
Git.

`tools/bootstrap-project.ps1` умеет использовать этот список как явную опору
для локальной установки конкретного рабочего проекта. Низкоуровневый
`tools/sync-to-project.ps1` остается path-based сценарием для точечного
обновления runtime-слоя.

## Что хранится в `template/project/.claude`

`template/project/.claude` содержит полный комплект Claude Code инструкций,
который устанавливается в рабочий проект.

Подходит:

- `.claude/CLAUDE.md` как project entry point;
- `AGENTS.md` как локальная входная инструкция Codex;
- переносимые agents;
- переносимые skills;
- переносимые core rules;
- supporting docs из `.claude/docs/*`, включая общий сценарий onboarding;
- шаблоны `.claude/rules/project/*`;
- шаблоны `.claude/rules/paths/*`;
- project entrypoint scripts из `.claude/scripts/*`, включая
  `commit-block.sh` и read-only helpers вроде `aidd-inspect.ps1`.
- deterministic hooks из `.claude/hooks/*`, подключенные через
  `.claude/settings.json`.

Не подходит:

- реальные PRD, plan, tasklist, research, feedback и review конкретных тикетов;
- secrets, credentials, локальные пути;
- `.claude/settings.local.json`;
- локальные permission rules в `.claude/settings.json`;
- machine-specific permissions;
- project-specific детали внутри переносимых `agents`, `skills` и `rules/core`.

## Разделение слоев

Переносимый runtime-слой физически лежит в проекте, но остается общим по смыслу:

- `.claude/agents` — роли subagent-ов и границы ответственности;
- `.claude/skills` — исполняемые пошаговые сценарии;
- `.claude/hooks` и `.claude/settings.json` — переносимые deterministic
  runtime guard-ы без локальных разрешений и machine-specific деталей;
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
- `.claude/settings.json`;
- `.claude/agents/*`;
- `.claude/hooks/*`;
- `.claude/skills/*`;
- `.claude/rules/core/*`;
- `.claude/rules/project/*`;
- `.claude/rules/paths/*`;
- `.claude/scripts/*`;
- `aidd/docs/<type>/<ticket>.md`;
- `aidd/docs/.active_ticket`.

Версионируемый `.claude/settings.json` используется только для переносимых
guard hooks. Локальные разрешения пользователя и машины должны оставаться в
`.claude/settings.local.json` или `~/.claude/settings.json` и не попадать в
этот шаблон.

## Правило для `.claude/scripts`

Если skill или agent вызывает скрипт по пути `.claude/scripts/<name>`, этот
скрипт должен поставляться через `template/project/.claude/scripts`.

Причина: `.claude/scripts/<name>` является путем внутри рабочего проекта.
Даже полностью переносимый helper должен быть установлен в проект, если
agents/skills обращаются к нему через `.claude/scripts/*`.

## Правило синхронизации шаблона

Claude Code подхватывает agents, skills, rules, hooks, settings и scripts из
стандартных каталогов `.claude`. Поэтому в рабочих проектах в одних и тех же
каталогах могут находиться и файлы шаблона, и project-local файлы:

- `.claude/CLAUDE.md`;
- `.claude/settings.json`;
- `.claude/agents/*`;
- `.claude/hooks/*`;
- `.claude/skills/*`;
- `.claude/rules/core/*`;
- `.claude/docs/*`;
- `.claude/scripts/*`.

Ownership определяется на уровне файла, а не каталога. Файл считается
принадлежащим шаблону, если файл с таким же относительным путем есть в
`template/project`.

При раскатке шаблона:

- файлы шаблона можно перезаписывать содержимым из `template/project`;
- project-local файлы, которых нет в `template/project`, нельзя удалять или
  изменять автоматически;
- отсутствие файла в шаблоне не означает, что такой файл нужно удалить из
  конечного проекта.

Если рабочий проект изменил файл с тем же относительным путем, что и в
`template/project`, например `.claude/agents/review-mr.md`, раскатка считает
его шаблонным и может перезаписать. Проектную конкретику лучше выносить в
`.claude/rules/project`, `.claude/rules/paths` или отдельный project-local
agent/skill/rule файл, которого нет в шаблоне.

В конечных проектах не следует добавлять корневой `CLAUDE.md` без отдельного
архитектурного решения. Шаблон использует `.claude/CLAUDE.md` как единственный
project entry point для Claude Code, чтобы не создавать два конкурирующих
источника project memory. Личные локальные заметки пользователя должны жить в
gitignored `CLAUDE.local.md` или локальных настройках, а проектная специфика —
в `.claude/rules/project` и `.claude/rules/paths`.

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
- `skills/aidd-fast-implement/SKILL.md`: добавлен короткий путь для простых
  `PRD_READY` defect-fix задач без создания `plan` и `tasklist`, с явным
  Fast path gate и одним запуском `implementer`.
- `rules/core/tool-usage.md`: добавлена общая политика выбора инструментов,
  запрет ad-hoc shell для file inspection и правило фиксации `Tooling gap`,
  если штатные `Read`/`Glob`/`Grep`/MCP tools неэффективны.
- `skills/1c-metadata-removal-impact/SKILL.md`: добавлена переносимая
  диагностика удаления элементов метаданных с gate для `USED` и `UNCLEAR`.
- `skills/review-gitlab-mr/SKILL.md`: добавлен ручной read-only сценарий
  review GitLab MR по ссылке через изолированный worktree и существующий
  `review-mr` engine.
- `skills/project-onboarding/SKILL.md`: добавлен Claude-вход в общий сценарий
  обследования проекта без смешивания фактов и догадок.

Подготовлены для `template/project/.claude/scripts`:

- `commit-block.sh`: убран универсальный default `src`; шаблон требует явный
  `--add-path` или проектную адаптацию безопасных default paths.
- `aidd-inspect.ps1`: проверен как read-only helper без project-specific
  маркеров.
- `scripts/README.md`: оставлен как описание project entrypoint scripts.

Подготовлены для `template/project`:

- `.claude/CLAUDE.md`: нейтральный project entry point, который ссылается на
  project-local `rules/core`, `skills`, `agents`, `rules/project`,
  `rules/paths` и `scripts`; добавлен always-loaded инвариант чтения
  AIDD-артефактов активного тикета через точные repo-relative пути без shell
  listing.
- `.claude/settings.json` и `.claude/hooks/*`: добавлен deterministic
  `PreToolUse` guard против inline shell file inspection.
- `.claude/rules/core/aidd-artifacts.md`: добавлен общий протокол чтения
  AIDD-артефактов активного тикета через `Read`/`Glob`, без `Bash`/`ls`/`dir`
  для проверки наличия файлов.
- `.claude/rules/core/tool-usage.md`: общий source of truth для выбора между
  `Read`, `Glob`, `Grep`, MCP, helper scripts и shell.
- `.claude/settings.json` и `.claude/hooks/block-inline-file-inspection.*`:
  добавлен `PreToolUse` hook, который блокирует inline shell для file
  inspection и возвращает агенту подсказку использовать
  `.claude/rules/core/tool-usage.md`.
- `AGENTS.md`: нейтральный Codex entry point для локальной настройки рабочих
  проектов.
- `.claude/docs/onboarding-project.md`: общий русскоязычный сценарий
  обследования 1С/EDT проекта и заполнения project/path rules.
- `.claude/rules/project/*`: нейтральные шаблоны `profile`, `ticketing`,
  `naming`, `change-policy`, `testing`, `pitfalls`,
  `onboarding-status`.
- `.claude/rules/paths/*`: README и нейтральный `source-example.md` без
  проектных путей.
- `aidd/docs/*/.gitkeep`: пустой каркас тикетных артефактов без
  `feedback/README.md`.

Подготовлены для `tools`:

- `sync-to-project.ps1`: dry-run/apply раскатка файлов шаблона в один рабочий
  проект по file-level ownership без удаления project-local файлов.
- `bootstrap-project.ps1`: локальная первичная установка проекта из
  `config/projects.local.json` или явного `-ProjectPath`; runtime-файлы
  обновляются, project-specific каркас создается только при отсутствии.

Осталось подготовить:

- `tools/check-shared.ps1`: автоматическая проверка переносимого runtime-слоя
  на случайную проектную специфику.
- `tools/sync-all-projects.ps1`: обновление проектов из локального списка.

## Контроль переносимого слоя

Перед установкой или массовым обновлением нужно проверять, что в переносимом
runtime-слое нет случайной проектной специфики. Минимальный набор маркеров для
проверки:

```text
CLIENT_A|PROJECT_X|PROJECT_Y|LEGACY_PREFIX|src/cf_edt|LOCAL_PREFIX_|DOMAIN_SAMPLE
```

Не каждое совпадение автоматически ошибка, но каждое должно быть осознанным и
обоснованным.
