# Личный AIDD-слой — входная точка Claude Code

## Назначение

Это входная точка личного AIDD-слоя поверх корпоративного agent layer MPL
Systems. Файл gitignored в рабочем проекте; его источник — шаблон
`1c-aidd-template`.

Личный слой — **надстройка**. Он не работает без корпоративного слоя и не
дублирует его: техническая процедура 1С/EDT живёт только в skills `mpl-*`, здесь
остаётся только AIDD-специфика.

Корпоративному слою принадлежат и личным слоем не изменяются:

- `AGENTS.md` в корне — корпоративная точка входа, читается Codex нативно;
- `.claude/CLAUDE.md` — корпоративный мост Claude Code (`@../AGENTS.md`);
- `.claude/rules/mpl/`, `.claude/skills/mpl-*`, `doc/ai/**` — корпоративные
  правила, skills и стандарты.

Файл должен оставаться коротким индексом и не дублировать подробные правила из
`.claude/rules/core`, `.claude/skills`, `.claude/agents`, project rules и
supporting docs.

## Слои конфигурации

- `core`: переносимые правила процесса AIDD и общие инженерные правила из
  `.claude/rules/core`.
- `project`: правила и ограничения именно этого репозитория.
- `paths`: path-scoped правила для отдельных зон дерева.
- `skills`: пошаговые исполняемые сценарии из `.claude/skills`.
- `agents`: роли subagent-ов с узкой зоной ответственности из `.claude/agents`.
- `hooks`: deterministic runtime guard-ы из `.claude/hooks`, подключенные через
  `.claude/settings.json`.
- `scripts`: project-local entrypoint scripts из `.claude/scripts`.
- `docs`: supporting docs.

Корпоративный слой (`AGENTS.md`, `.claude/rules/mpl/`, `.claude/skills/mpl-*`,
`doc/ai/**`) загружается параллельно и независимо. Личные правила не отключают
корпоративные skills `mpl-*` и правила безопасности; при конфликте вынеси вопрос
пользователю.

## Где искать source of truth

- AIDD workflow и lifecycle артефактов:
  `.claude/rules/core/aidd-workflow.md`
  `.claude/rules/core/aidd-artifacts.md`
- Общие правила review, git, code style и 1С/EDT:
  `.claude/rules/core/*.md`
- Выбор инструментов, shell policy и фиксация tooling gaps:
  `.claude/rules/core/tool-usage.md`
- Профиль проекта, change policy, naming, ticketing, testing, pitfalls:
  `.claude/rules/project/*.md`
- Path-scoped ограничения:
  `.claude/rules/paths/*.md`
- Исполняемые AIDD-сценарии:
  `.claude/skills/aidd-*/SKILL.md`
- Специализированные skills:
  `.claude/skills/mpl-1c-bsp/SKILL.md` (корпоративный)
  `.claude/skills/1c-debug-info-tools/SKILL.md`
  `.claude/skills/mpl-1c-query/SKILL.md` (корпоративный)
  `.claude/skills/mpl-metadata-removal-impact/SKILL.md` (корпоративный)
  `.claude/skills/mpl-edt-companion-mcp/SKILL.md` (корпоративный)
  `.claude/skills/mpl-edt-mcp/SKILL.md` (корпоративный)
  `.claude/skills/mpl-1c-rsv/SKILL.md` (корпоративный)
  `.claude/skills/mpl-v8std/SKILL.md` (корпоративный)
  `.claude/skills/mpl-yaxunit/SKILL.md`
  `.claude/skills/review-mr/SKILL.md`
  `.claude/skills/review-gitlab-mr/SKILL.md`
  `.claude/skills/sonar-pr-evidence/SKILL.md`
  `.claude/skills/gitlab-tools/SKILL.md`
  `.claude/skills/release-mr/SKILL.md`
  `.claude/skills/project-onboarding/SKILL.md`
- Роли subagent-ов:
  `.claude/agents/*.md`
- Project entrypoint scripts:
  `.claude/scripts/*`
- Project hooks:
  `.claude/settings.json`
  `.claude/hooks/*`
- Артефакты активного тикета:
  `aidd/docs/.active_ticket`
  `aidd/docs/{prd,plan,tasklist,research,feedback,debug,review}/*`

## Роутинг сценариев

- Если пользователь сообщает замечание по активному тикету, обсуждает feedback,
  пишет "фиксируем", "добавляем", "берем в работу" или "давай сделаем" в
  контексте замечаний, это сценарий `aidd-fix-feedback`.
- В таком случае сначала прочитай `.claude/skills/aidd-fix-feedback/SKILL.md`.
- До записи `FB-XXX` в `aidd/docs/feedback/<ticket>.md` не редактируй `src/`,
  `tasklist`, `review` и другие артефакты реализации.
- Слово "фиксируем" в контексте замечаний означает "зафиксировать в feedback",
  а не "сразу внести правку в код".
- Если пользователь просит автономно запускать тест, smoke, HTTP-проверку,
  YAxUnit, project-local script или другой runner и исправлять до PASS без
  участия пользователя, это сценарий `aidd-debug-loop`.
- В таком случае сначала прочитай `.claude/skills/aidd-debug-loop/SKILL.md`.
- `debug-loop` не заменяет `feedback-fix`: пользовательские замечания идут в
  `feedback`, машинный trace runner-ов идёт в `aidd/docs/debug/<ticket>.md`.
- Если пользователь просит посмотреть замечания GitLab merge request, проверить
  их исправленность, ответить ревьюеру, узнать статус пайплайна или разобрать
  падение CI, это сценарий `gitlab-tools`. Замечание ревьюера GitLab — внешняя
  находка: оно идёт в `review`, а не в `feedback`. Эта маршрутизация имеет
  приоритет над общим правилом `feedback`.
- Если пользователь передал GitLab MR URL и просит провести review самого
  change-set, сначала прочитай `.claude/skills/review-gitlab-mr/SKILL.md`.
  Этот read-only сценарий может использовать только verified Sonar evidence по
  `.claude/skills/sonar-pr-evidence/SKILL.md`; он не запускает
  `aidd-fix-sonar`, не создаёт `RV-XXX` и не исправляет код.
- Если пользователь явно просит подготовить или создать релизные MR, сначала
  прочитай `.claude/skills/release-mr/SKILL.md`. Сценарий доступен только при
  заполненной секции «Релизные MR» в `.claude/rules/project/ticketing.md`.

## Обязательный routing skills

### EDT MCP routing

Для metadata, СКД, форм, ролей, подсистем и BSL используй ровно один EDT MCP,
заданный в project-local `.mcp.json`. Из трёх имён
`edt-companion-mcp`, `edt-mcp`, `1c-rsv` в `mcpServers` должно быть ровно одно.

| Сервер в `.mcp.json` | Обязательный skill | Допустимые tools |
| --- | --- | --- |
| `edt-companion-mcp` | `mpl-edt-companion-mcp` | `mcp__edt-companion-mcp__*` |
| `edt-mcp` | `mpl-edt-mcp` | `mcp__edt-mcp__*` |
| `1c-rsv` | `mpl-1c-rsv` | `mcp__1c-rsv__*` |

Не выбирай другой EDT MCP из-за недоступности, непокрытой операции, ошибки или
неполного результата выбранного сервера. Зафиксируй limitation/tooling gap и
перейди к штатному project fallback по `.claude/rules/core/tool-usage.md`.
Если в `.mcp.json` нет ни одного или указано два и более EDT MCP, это ошибка
конфигурации: EDT-вызовы запрещены до её исправления. Hook из
`.claude/settings.json` технически блокирует вызовы невыбранного сервера.

Перед редкой или рискованной операцией сверяй фактическую schema выбранного
сервера. Не смешивай его write API с файловым fallback внутри одного change
block для объекта или модуля: переход выполняй только на границе целой
операции с повторным чтением фактического состояния.

Прямая правка `*.mdo`, `*.form`, `*.dcs` через `Write`/`Edit` запрещена, если
выбранный MCP покрывает операцию `edit_metadata`. Запуски изменения ИБ, полного
rebuild, YAxUnit и debugger принимает только основная сессия по решению
пользователя; subagent их не вызывает.

`Read` известного файла и `Glob` узкого известного пути допустимы без skill.
Широкий `Glob`/`Grep` по 1С-исходникам используй только при недоступности
выбранного MCP или для подтверждения уже найденных им кандидатов.

### mpl-1c-bsp

Если задача затрагивает стандартные подсистемы БСП, переопределяемые модули,
project-wrapper-ы БСП, варианты отчетов, работу с файлами, безопасное
хранилище, подключаемые команды, общие формы БСП или вспомогательные данные
БСП в ИБ, используй корпоративный skill `mpl-1c-bsp`.

`mpl-1c-bsp` задает БСП-контракты и чеклисты, но не навязывает конкретный
инструмент. Для metadata, СКД, форм, ролей и BSL используй EDT MCP, выбранный
в `.mcp.json`; при его недоступности действуй через разрешенный project
fallback.

### mpl-v8std

Для сверки паттерна кода со стандартами 1С, расшифровки кодов диагностик
(BSLLS, АПК, EDT/v8-code-style) и разрешения споров «стандарт или вкус»
используй корпоративный skill `mpl-v8std`, если MCP `v8std` доступен.
Это read-only база знаний без привязки к рабочей копии; она разрешена и в
review-сценариях с изолированным worktree.

### 1c-debug-info-tools

Если MCP `1c-debug-info` доступен и задача связана с runtime-диагностикой
живой 1С базы, журналом регистрации, HTTP-smoke/YAxUnit падением или
расхождением между EDT-исходниками и фактической ИБ, используй
`.claude/skills/1c-debug-info-tools/SKILL.md` как дополнительный источник
evidence.

`1c-debug-info` не заменяет выбранный EDT MCP: код, метаданные EDT, формы,
СКД, роли и BSL-правки остаются в его зоне. Runtime
evidence связывай с исходниками через EDT-слой, `Read` или другой разрешенный discovery.

### YAxUnit

Любое содержательное действие, связанное с YAxUnit, выполняй через
`.claude/skills/mpl-yaxunit/SKILL.md`.

Это относится не только к редактированию кода, но и к анализу, планированию,
review, интерпретации тестов, формулированию feedback/review-рекомендаций,
выбору assertions, моков, test doubles и тестовых данных.

Триггеры: `YAxUnit`, `модульный тест`, `юнит-тест`, `тестовый модуль`,
`src/cfe/yaxunit/**`, `tests/smoke/**`, `Мокито`, `ЮТест.Данные()`,
`ЮТест.ОжидаетЧто()`, `ЮТТесты`, `ИсполняемыеСценарии`, HTTP-моки YAxUnit.
Одного `&Вместо` недостаточно для выбора YAxUnit: оно относится к этому skill
только в контексте Мокито или тестового расширения.

Обычный поиск файлов или проверка наличия тестов может выполняться без skill.
Как только нужно сделать технический вывод, рекомендацию, план или правку,
сначала примени `mpl-yaxunit/SKILL.md`.

`references/yaxunit-api.md` является справочником и не заменяет
`mpl-yaxunit/SKILL.md`.

## Приоритет источников

При конфликте ориентируйся в таком порядке:

1. Явные указания пользователя в текущем диалоге.
2. Артефакты активного тикета в `aidd/docs/`.
3. Применимые path rules из `.claude/rules/paths/*.md`.
4. Project rules из `.claude/rules/project/*.md`.
5. Core rules из `.claude/rules/core/*.md`.
6. Skill или agent, который выполняет текущий сценарий.
7. Supporting docs из `.claude/docs/*.md`.

Корпоративные правила безопасности и skills `mpl-*` не отключаются ни одним
пунктом этого списка. Если личное правило противоречит корпоративному
инварианту, вынеси вопрос пользователю.

## Минимальные always-loaded инварианты

- Не дублируй длинные project-specific инструкции в этом файле.
- Для каждого типа правил должен быть один основной source of truth.
- Если path rule, project rule или текущий сценарий требует использовать skill,
  сначала прочитай соответствующий `SKILL.md` и следуй его workflow/checklist.
  Чтение файлов из `references/`, supporting docs или примеров не заменяет
  применение skill.
- AIDD-артефакты активного тикета читай по точным repo-relative путям через
  `Read`/`Glob` по `.claude/rules/core/aidd-artifacts.md`; не используй
  `Bash`, `ls`, `dir`, `Get-ChildItem`, `Test-Path`, `rg --files` или shell
  redirects/pipelines только для проверки их наличия.
- Известные файлы и их фрагменты инспектируй через `Read`/`Glob`/`Grep`/MCP по
  `.claude/rules/core/tool-usage.md`; не используй `Bash`, PowerShell или
  `python -c` для file slicing, byte dumps, проверки кодировки или ad-hoc
  чтения файла. Если штатные tools неэффективны, зафиксируй `Tooling gap`.
- Если в ходе работы выяснилось, что обязательный skill был пропущен, останови
  изменение, прочитай skill и перепроверь уже принятое решение по его правилам.
- `.claude/settings.json` содержит `PreToolUse` guard для `Bash`, который
  блокирует inline shell file inspection. Если hook вернул отказ, перестрой
  действие по `.claude/rules/core/tool-usage.md`, а не проси пользователя
  разрешить blocked command.
- В финальном ответе для задач, где сработали обязательные rules/skills, кратко
  укажи применённые skills и ключевые rules.
- Новые длинные инструкции добавляй в подходящий `rule`, `skill`, `agent` или
  `docs`-файл, а не в этот индекс.
- Новый общий пошаговый сценарий добавляй в `.claude/skills/*`.
- Новый общий role-specific контракт добавляй в `.claude/agents/*`; agent не
  должен быть вторым хранилищем project policy.
- Новые project-specific ограничения добавляй в `.claude/rules/project/*` или
  `.claude/rules/paths/*`, а не в `.claude/agents/*`, `.claude/skills/*` или
  supporting docs.
- Перед добавлением нового файла сначала проверь, нельзя ли расширить уже
  существующий source of truth без дублирования.

## Supporting docs

- Supporting docs:
  `.claude/docs/onboarding-project.md`
  `.claude/docs/*.md`
