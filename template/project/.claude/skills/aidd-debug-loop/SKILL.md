---
name: aidd-debug-loop
description: >
  Автономный цикл отладки в рамках AIDD: запуск заданного теста, runner или
  smoke-проверки, анализ результата, запись диагноза и рекомендации в
  aidd/docs/debug/<ticket>.md, исправление через debug-fixer без commit и
  повторный запуск до PASS или blocker. Используй, когда пользователь просит
  автоматизировать отладку, прогонять тесты/HTTP-smoke/YAxUnit/скрипты до
  зелёного результата или выполнить test-in-the-loop debug без участия
  пользователя.
---

# AIDD Debug Loop

Используй subagent `debug-fixer` для исправления одной диагностированной
проблемы. Оркестрация, запуск проверок, анализ результата и обновление
`aidd/docs/debug/<ticket>.md` остаются в основной сессии.

Source of truth:

- `.claude/rules/core/aidd-workflow.md`
- `.claude/rules/core/aidd-artifacts.md`
- `.claude/rules/core/tool-usage.md`
- `.claude/rules/core/code-style.md`
- `.claude/rules/project/testing.md`
- `.claude/rules/project/change-policy.md`
- `.claude/rules/project/naming.md`
- `.claude/rules/paths/*.md`
- `.claude/skills/1c-debug-info-tools/SKILL.md` — только если доступен
  `1c-debug-info` и runtime/log диагностика входит в scope проверки.

## Назначение

`aidd-debug-loop` нужен для автономного цикла:

`run check -> analyze failure -> write diagnosis/recommendation -> fix -> run check`

Сценарий не заменяет `feedback-fix`. `feedback` хранит пользовательские
замечания и требует решения пользователя. `debug` хранит машинный trace
проверок, диагнозов и исправлений.

## Входные условия

Перед запуском должен быть явно задан способ проверки:

- в `plan`, `tasklist`, PRD, `debug`-артефакте или прямой команде пользователя;
- с конкретной командой, project-local script, YAxUnit runner, HTTP-smoke
  runner, MCP/log шагом или другой проверяемой процедурой;
- с ожидаемым PASS-критерием и допустимой зоной изменений.

Если способ проверки не задан, не изобретай runner. Верни blocker и попроси
сначала зафиксировать, что запускать и чем подтверждается успех.

Project-specific запреты и разрешения из `.claude/rules/project/testing.md`
обязательны. Если проект запрещает агентам запускать тесты или внешние
проверки, debug-loop можно запускать только после project-specific
разрешения или через явно разрешённый runner.

## Лимиты

По умолчанию:

- `maxIterations = 5` — максимум запусков проверки за один debug-loop;
- `maxFixAttemptsPerIssue = 2` — максимум попыток исправить одну и ту же
  диагностированную проблему.

Переопределяй лимиты только если они явно указаны в plan/tasklist/debug-задании
или пользователем. Не снимай лимиты полностью.

Итерация считается потраченной после каждого запуска проверки, независимо от
результата.

Одна и та же проблема считается повторяющейся, если совпадает стабильный
симптом: тест/runner, код ошибки, HTTP status, сообщение исключения, ключевой
фрагмент лога или диагностированная причина.

## Артефакт debug

Результаты фиксируются в `aidd/docs/debug/<ticket>.md`.

Если файла нет, создай его со структурой:

```markdown
# Debug: <ticket> — <краткая тема>

Ticket: <ticket>
Status: DEBUG_IN_PROGRESS
Started: <date>

## Scope

- Runner:
- PASS criteria:
- Allowed changes:
- Limits: maxIterations=<N>, maxFixAttemptsPerIssue=<N>

## Iterations
```

Для HTTP-smoke сценариев расширь структуру перед `Iterations`:

```markdown
## Scope

- Runner: `.claude/scripts/http-smoke.cmd`.
- Config/Profile: `.claude/config/http-smoke.local.json`, profile `<name>`.
- EndpointPath:
- Fixtures: `aidd/fixtures/<ticket>/`.
- PASS criteria:
- Allowed changes:
- Limits:

## Pre-flight

1. Локальный config/profile существует и не содержит секретов.
2. Dev/test стенд синхронизирован пользователем.
3. Секреты, если нужны, заданы через env vars из config.

## Test plan

| # | Fixture | Method | Expected status | Expected substring | AC |
| --- | --- | --- | --- | --- | --- |
```

Запуск HTTP-smoke должен использовать `-Profile <name>` и
`-EndpointPath <path>`; `-Url` и `-BaseUrl` допустимы как разовый override,
но не как основной способ хранения стендов в AIDD-артефактах.

Для каждой итерации добавляй запись:

```markdown
### Iteration <N> — <PASS|FAIL|BLOCKED>

- Run:
- Result:
- Evidence:
- Diagnosis:
- Recommendation:
- Decision: <FIX_CODE|FIX_TEST|FIX_FIXTURE|FIX_RUNNER|NO_CHANGE|BLOCKER|PASS>
- Fix attempt for issue: <issue-key>, attempt <n>/<limit>
- Changed files:
- Next step:
```

Диагноз и рекомендацию нужно записать до любых правок по этой итерации.
Не переписывай старые диагнозы задним числом; если вывод изменился после
новых данных, добавь новую запись.

## Алгоритм

1. Определи ticket id: используй переданный аргумент или
   `aidd/docs/.active_ticket`.
2. Прочитай PRD, plan, tasklist, research, feedback/review при наличии и
   `aidd/docs/debug/<ticket>.md`, если он уже существует.
3. Прочитай `.claude/rules/project/testing.md` и убедись, что выбранный runner
   разрешён для проекта или явно задан пользователем в текущем scope.
4. Определи runner, PASS-критерии, allowed changes и лимиты. Если чего-то нет,
   остановись с blocker.
5. Запусти проверку самым узким разрешённым способом:
   - project-local script из `.claude/scripts/*`;
   - YAxUnit runner, если он доступен и разрешён;
   - HTTP-smoke runner, если он явно задан;
   - MCP/log/read-only диагностику, если она указана как часть проверки;
   - для runtime-ошибок 1С используй `1c-debug-info-tools`, если MCP
     `1c-debug-info` доступен и это не расширяет scope проверки.
6. Если результат PASS:
   - запиши PASS-итерацию;
   - проверь, что diff не вышел за allowed changes;
   - переведи debug-артефакт в `DEBUG_PASS`;
   - заверши без commit.
7. Если результат FAIL:
   - проанализируй evidence;
   - классифицируй причину: production-код, тест, fixture/test data,
     runner/environment, external dependency или unknown;
   - запиши diagnosis, recommendation и decision в debug-артефакт до правок.
8. Если decision требует правки, проверь лимиты. При превышении лимита запиши
   `BLOCKER` и остановись.
9. Запусти `debug-fixer` со scope ровно одной записанной рекомендации.
   - если правка затрагивает YAxUnit-тесты, тестовое расширение, Мокито,
     `ЮТест.Данные()`, assertions, test doubles или YAxUnit API, явно укажи
     `debug-fixer`, что он обязан применить
     `.claude/skills/mpl-yaxunit/SKILL.md`;
   - для API YAxUnit, Мокито, HTTP-моков, `HTTPОтвет`, `HTTPСервисЗапрос` или
     `&Вместо` отдельно укажи прочитать
     `.claude/skills/mpl-yaxunit/references/yaxunit-api.md`.
10. Проверь результат `debug-fixer`: diff, scope, отсутствие самовольных
    изменений и `Tooling gap`. Для выбранного EDT MCP bug/drift/gap/idea/performance
    зафиксируй literal evidence до следующего runner или fallback.
11. Обнови debug-итерацию: фактические changed files, tooling gaps, EDT MCP
    observation (если есть) и next step; добавь ссылку на каноническую запись
    research, если он есть, иначе PRD.
12. Повтори цикл с шага 5, пока не будет PASS, blocker или лимит итераций.

## Правила исправлений

- Не подгоняй тест под текущий ошибочный результат.
- Тест, fixture или runner исправляй только если диагноз показывает, что
  проблема именно в них.
- Production-код исправляй только если падение указывает на нарушение
  согласованного поведения, PRD, test plan или внешнего контракта.
- Если результат зависит от бизнес-решения, изменения scope, спорного
  ожидания или внешнего факта без доступного источника, остановись с blocker.
- Если runner нестабилен или окружение не готово, не маскируй это правкой кода:
  запиши environment/tooling blocker.
- MCP/БД/журнал регистрации являются опциональными источниками диагностики,
  только если они явно доступны и указаны в плане проверки. Для журнала
  регистрации и структуры живой ИБ предпочитай `1c-debug-info-tools`, но не
  подключай generic SQL или новые внешние инструменты самовольно.

## Завершение

Успех debug-loop означает:

- все проверки, заданные текущим debug/test plan, вернули PASS;
- diff остался в allowed changes;
- debug-артефакт содержит trace всех итераций;
- commit не сделан.

Если цикл завершился blocker:

- оставь статус `DEBUG_BLOCKED`;
- зафиксируй последнюю evidence, причину остановки, исчерпанные лимиты или
  недостающее решение;
- не создавай `feedback` автоматически, если пользователь явно не просит
  перевести blocker в human feedback.

## Финальный ответ

Сообщи:

- итоговый статус `DEBUG_PASS` или `DEBUG_BLOCKED`;
- сколько итераций и исправлений выполнено;
- какие файлы изменены;
- какие проверки запускались;
- что осталось проверить вручную, если это явно требуется test plan.

Не делай `git commit`.
