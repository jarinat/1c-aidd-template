# <Project Name> - Claude Code Entry Point

## Назначение

Это главная project-shared входная точка для Claude Code в этом репозитории.
Файл должен оставаться коротким индексом и не дублировать подробные правила из
`.claude/rules/core`, `.claude/skills`, `.claude/agents`, project rules и
supporting docs.

В рамках проекта используется именно `.claude/CLAUDE.md`, а не корневой
`CLAUDE.md`.

## Слои конфигурации

- `core`: переносимые правила процесса AIDD и общие инженерные правила из
  `.claude/rules/core`.
- `project`: правила и ограничения именно этого репозитория.
- `paths`: path-scoped правила для отдельных зон дерева.
- `skills`: пошаговые исполняемые сценарии из `.claude/skills`.
- `agents`: роли subagent-ов с узкой зоной ответственности из `.claude/agents`.
- `scripts`: project-local entrypoint scripts из `.claude/scripts`.
- `docs`: supporting docs.

## Где искать source of truth

- AIDD workflow и lifecycle артефактов:
  `.claude/rules/core/aidd-workflow.md`
  `.claude/rules/core/aidd-artifacts.md`
- Общие правила review, git, code style и 1С/EDT:
  `.claude/rules/core/*.md`
- Профиль проекта, change policy, naming, ticketing, testing, pitfalls:
  `.claude/rules/project/*.md`
- Path-scoped ограничения:
  `.claude/rules/paths/*.md`
- Исполняемые AIDD-сценарии:
  `.claude/skills/aidd-*/SKILL.md`
- Специализированные skills:
  `.claude/skills/1c-query/SKILL.md`
  `.claude/skills/1c-metadata-removal-impact/SKILL.md`
  `.claude/skills/rlm-tools-bsl/SKILL.md`
  `.claude/skills/yaxunit-tests/SKILL.md`
  `.claude/skills/edt-form-editing/SKILL.md`
  `.claude/skills/review-mr/SKILL.md`
  `.claude/skills/review-gitlab-mr/SKILL.md`
  `.claude/skills/project-onboarding/SKILL.md`
- Роли subagent-ов:
  `.claude/agents/*.md`
- Project entrypoint scripts:
  `.claude/scripts/*`
- Артефакты активного тикета:
  `aidd/docs/.active_ticket`
  `aidd/docs/{prd,plan,tasklist,research,feedback,review}/*`

## Роутинг сценариев

- Если пользователь сообщает замечание по активному тикету, обсуждает feedback,
  пишет "фиксируем", "добавляем", "берем в работу" или "давай сделаем" в
  контексте замечаний, это сценарий `aidd-fix-feedback`.
- В таком случае сначала прочитай `.claude/skills/aidd-fix-feedback/SKILL.md`.
- До записи `FB-XXX` в `aidd/docs/feedback/<ticket>.md` не редактируй `src/`,
  `tasklist`, `review` и другие артефакты реализации.
- Слово "фиксируем" в контексте замечаний означает "зафиксировать в feedback",
  а не "сразу внести правку в код".

## Обязательный routing skills

### rlm-tools-bsl

Все 1С/EDT проекты этого шаблона по умолчанию считаются большими кодовыми
базами.

Для смыслового discovery по 1С/EDT-кодовой базе сначала примени
`.claude/skills/rlm-tools-bsl/SKILL.md`, если MCP `rlm-tools-bsl` доступен.

Это относится к `/aidd-idea`, preliminary technical reconnaissance, подготовке
research, поиску точек использования, ссылок на метаданные, форм, движений,
подписок, callers, интеграций и локальных reference patterns.

В основной сессии не собирай большие фрагменты 1С-кода вручную до запуска
subagent. Сначала сузь область через AIDD-артефакты и `rlm-tools-bsl`, затем
передавай в agent краткую discovery-сводку: project/path, состояние индекса,
найденные объекты, методы, формы, узкие файлы-кандидаты и ограничения проверки.

`Read` известного файла и `Glob` узкого известного пути допустимы без skill.
Широкий `Glob`/`Grep` по `src`, `src/cf`, `src/cfe` для поиска 1С-сущностей
используй только как fallback, если MCP недоступен, или для подтверждения уже
найденных MCP-кандидатов.

### YAxUnit

Любое содержательное действие, связанное с YAxUnit, выполняй через
`.claude/skills/yaxunit-tests/SKILL.md`.

Это относится не только к редактированию кода, но и к анализу, планированию,
review, интерпретации тестов, формулированию feedback/review-рекомендаций,
выбору assertions, моков, test doubles и тестовых данных.

Триггеры: `YAxUnit`, `модульный тест`, `юнит-тест`, `тестовый модуль`,
`src/cfe/yaxunit/**`, `tests/smoke/**`, `Мокито`, `ЮТест.Данные()`,
`ЮТест.ОжидаетЧто()`, `HTTPОтвет`, `HTTPСервисЗапрос`, `&Вместо`.

Обычный поиск файлов или проверка наличия тестов может выполняться без skill.
Как только нужно сделать технический вывод, рекомендацию, план или правку,
сначала примени `yaxunit-tests/SKILL.md`.

`references/api-reference.md` является справочником и не заменяет
`yaxunit-tests/SKILL.md`.

## Приоритет источников

При конфликте ориентируйся в таком порядке:

1. Явные указания пользователя в текущем диалоге.
2. Артефакты активного тикета в `aidd/docs/`.
3. Применимые path rules из `.claude/rules/paths/*.md`.
4. Project rules из `.claude/rules/project/*.md`.
5. Core rules из `.claude/rules/core/*.md`.
6. Skill или agent, который выполняет текущий сценарий.
7. Supporting docs из `.claude/docs/*.md`.

## Минимальные always-loaded инварианты

- Не дублируй длинные project-specific инструкции в этом файле.
- Для каждого типа правил должен быть один основной source of truth.
- Если path rule, project rule или текущий сценарий требует использовать skill,
  сначала прочитай соответствующий `SKILL.md` и следуй его workflow/checklist.
  Чтение файлов из `references/`, supporting docs или примеров не заменяет
  применение skill.
- Если в ходе работы выяснилось, что обязательный skill был пропущен, останови
  изменение, прочитай skill и перепроверь уже принятое решение по его правилам.
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
