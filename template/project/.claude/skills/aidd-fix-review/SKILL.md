---
name: aidd-fix-review
description: >
  Исправление принятого замечания из review в рамках AIDD. Используй для
  сценария review-fix: обработать одно RV-замечание без commit и без изменения
  tasklist.
---

# AIDD Fix Review

Используй subagent `review-fixer`.

Source of truth для lifecycle `review` и статусов:

- `.claude/rules/core/aidd-workflow.md`
- `.claude/rules/core/aidd-artifacts.md`
- `.claude/rules/core/tool-usage.md`

## Ключевые правила

- Один запуск = одно замечание `RV-XXX`.
- Этот workflow не обновляет `tasklist` и не делает commit.
- Не запускай `implementer` внутри этого сценария.
- Исправлять можно только замечание, уже готовое к циклу review-fix по
  правилам AIDD.
- Повторный review не запускается автоматически.

## Алгоритм

1. Определи ticket id: используй переданный аргумент или `aidd/docs/.active_ticket`.
2. Определи целевую запись `RV-XXX`:
   - используй переданный аргумент, если он есть;
   - иначе используй явно упомянутый пользователем `RV-XXX`;
   - если однозначно определить нельзя, задай один короткий уточняющий вопрос.
3. Прочитай `aidd/docs/review/<ticket>.md` и найди целевую запись.
4. Убедись, что статус записи допускает запуск review-fix.
5. Прочитай связанный код и контекст тикета.
6. Запусти `review-fixer` со scope ровно текущего `RV-XXX`.
   - если замечание затрагивает YAxUnit-тесты, тестовое расширение, Мокито,
     `ЮТест.Данные()`, assertions, test doubles или YAxUnit API, явно укажи
     `review-fixer`, что он обязан применить
     `.claude/skills/yaxunit-tests/SKILL.md`;
   - чтение `.claude/skills/yaxunit-tests/references/api-reference.md` не
     заменяет применение `.claude/skills/yaxunit-tests/SKILL.md`;
   - для API YAxUnit, Мокито, HTTP-моков, `HTTPОтвет`, `HTTPСервисЗапрос` или
     `&Вместо` отдельно укажи прочитать
     `.claude/skills/yaxunit-tests/references/api-reference.md`.
7. Проверь результат.
8. Обнови запись в `aidd/docs/review/<ticket>.md` по правилам AIDD:
   - зафиксируй, что изменено;
   - перечисли затронутые файлы;
   - если `review-fixer` сообщил `Tooling gap`, зафиксируй его в записи
     `RV-XXX` отдельным полем или подпунктом;
   - для наблюдения A-COMP зафиксируй краткий факт в `RV-XXX` до fallback и
     сошлись на каноническую запись в research, если он есть, иначе в PRD в
     разделе `Implementation notes / Tooling observations / A-COMP`;
   - переведи статус замечания в целевой статус.
9. Сообщи пользователю, что изменено, и отдельно укажи, что повторный review
   запускается только вручную по его команде.
