# AIDD artifacts and statuses

Этот файл описывает артефакты тикета и связанные с ними статусы процесса.

## Артефакты

- PRD: `aidd/docs/prd/<ticket>.prd.md`  
  Статус: `PRD_READY`
- Research: `aidd/docs/research/<ticket>.md`  
  Опционально
- Plan: `aidd/docs/plan/<ticket>.md`  
  Статус: `PLAN_APPROVED`
- ADR: `aidd/docs/adr/<ticket>.md`  
  Опционально
- Tasklist: `aidd/docs/tasklist/<ticket>.md`  
  Статус: `TASKLIST_READY`
- Feedback: `aidd/docs/feedback/<ticket>.md`  
  Содержит замечания пользователя и их решения
- Debug: `aidd/docs/debug/<ticket>.md`
  Содержит trace автономных test/debug-loop итераций
- Review: `aidd/docs/review/<ticket>.md`  
  Содержит замечания внутреннего review и решения по ним
- Fixtures: `aidd/fixtures/<ticket>/`
  Опциональные test payloads и данные для debug-loop, HTTP-smoke, smoke или
  других явно заданных runner-ов

## Протокол чтения AIDD-артефактов

Для активного тикета AIDD-артефакты читаются по точным repo-relative путям, а
не через перечисление каталогов.

Алгоритм:

1. Сначала прочитай `aidd/docs/.active_ticket`, если ticket id явно не передан
   пользователем или текущим skill.
2. Построй точные пути по ticket id:
   - `aidd/docs/prd/<ticket>.prd.md`
   - `aidd/docs/research/<ticket>.md`
   - `aidd/docs/plan/<ticket>.md`
   - `aidd/docs/tasklist/<ticket>.md`
   - `aidd/docs/feedback/<ticket>.md`
   - `aidd/docs/debug/<ticket>.md`
   - `aidd/docs/review/<ticket>.md`
3. Required-артефакты читай прямым `Read` точного файла. Если required-файл
   отсутствует, это blocker или основание выбрать другой AIDD-сценарий.
4. Optional-артефакты проверяй прямым `Read` точного файла. Если файл
   отсутствует, считай артефакт отсутствующим и продолжай по правилам текущего
   сценария.
5. `Glob` допустим только если ticket id неизвестен, артефакт имеет
   legacy/нестандартное имя или нужно найти несколько кандидатов по явной
   причине.

Не используй `Bash`, `ls`, `dir`, `Get-ChildItem`, `Test-Path`, `rg --files`,
shell brace expansion, redirects или pipelines только для проверки наличия
AIDD-артефактов активного тикета. Это read-only lifecycle discovery и оно
должно выполняться через `Read`/`Glob` без shell-команд и лишних permission
prompt.

## Минимальный набор перед реализацией

Перед переходом к `implement` должны существовать и быть готовы:

- PRD со статусом `PRD_READY`
- Plan со статусом `PLAN_APPROVED`
- Tasklist со статусом `TASKLIST_READY`

Исключение: перед переходом к `fast-implement` достаточно PRD со статусом
`PRD_READY`, если текущий тикет проходит все критерии `Fast path` из
`.claude/rules/core/aidd-workflow.md` и пользователь явно согласовал короткий
путь. В этом сценарии `plan` и `tasklist` не создаются.

PRD нельзя переводить в `PRD_READY`, если в нём есть `Blocking questions` или
неразрешённые противоречия входного контекста, влияющие на scope, бизнес-правила,
формулы, данные или acceptance criteria.

## Feedback и review

- `feedback` — отдельный артефакт для пользовательских замечаний и их
  последующей фиксации.
- `feedback` хранит полный цикл пользовательского замечания: исходный текст,
  анализ причины, рекомендацию, решение пользователя, фактическое исправление,
  проверку и кандидатов в базу знаний.
- Для записей `feedback` используются только статусы `OPEN`, `RESOLVED` и
  `DECLINED`.
- `RESOLVED` допустим только после явного подтверждения пользователя и, если
  были правки кода, при заполненном фактическом исправлении.
- Рекомендация и фактическое исправление могут отличаться; сохраняй оба поля
  отдельно и не переписывай рекомендацию задним числом.
- `review` — отдельный артефакт для замечаний внутреннего review.
- `feedback` и `review` не смешиваются в одном файле и не заменяют друг друга.

## Debug

- `debug` — отдельный артефакт для автономных проверок, которые запускает
  основная сессия: YAxUnit, HTTP-smoke, project-local script, MCP/log
  диагностика или другой явно заданный runner.
- Если debug-loop использует test data, они должны лежать в
  `aidd/fixtures/<ticket>/` и быть описаны в `README.md` или в таблице
  test plan debug-артефакта. Machine-specific URL, креды и токены в fixtures
  не записываются.
- `debug` хранит машинный trace: запуск, результат, evidence, диагноз,
  рекомендацию, decision, фактическое исправление и следующий шаг.
- `debug` не заменяет `feedback`: пользовательские замечания не записываются в
  `debug`, а машинные падения runner-а не требуют пользовательского согласия,
  если они остаются в заранее заданном test/debug scope.
- Диагноз и рекомендация по итерации должны быть записаны в
  `aidd/docs/debug/<ticket>.md` до правок по этой итерации.
- Для `debug` используются статусы `DEBUG_IN_PROGRESS`, `DEBUG_PASS` и
  `DEBUG_BLOCKED`.
- `DEBUG_PASS` допустим только когда все проверки, заданные текущим
  test/debug plan, вернули PASS, а diff не вышел за allowed changes.
- `DEBUG_BLOCKED` ставится при исчерпании лимитов, неготовом окружении,
  невозможности безопасной диагностики, необходимости business/scope решения
  или отсутствии явно заданного runner-а.
- Debug-loop не делает `git commit`.

## Использование в работе

Перед любой работой по активному тикету нужно прочитать:

1. `aidd/docs/.active_ticket`
2. PRD, plan и tasklist по тикету
3. `aidd/docs/feedback/<ticket>.md`, `aidd/docs/debug/<ticket>.md` и
   `aidd/docs/review/<ticket>.md`, если эти файлы уже существуют
4. Перед планированием или реализацией проверь, нет ли в PRD раздела
   `Blocking questions`. Если он не пустой, не продолжай затронутую часть без
   явного решения пользователя.

Все чтения и проверки наличия AIDD-артефактов выполняй по протоколу из раздела
`Протокол чтения AIDD-артефактов`.

Для `fast-implement` вместо `plan` и `tasklist` нужно прочитать PRD, проверить
их отсутствие как ожидаемое состояние короткого пути и зафиксировать результат
Fast path gate перед запуском `implementer`.
