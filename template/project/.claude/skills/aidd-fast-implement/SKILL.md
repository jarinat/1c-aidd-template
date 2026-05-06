---
name: aidd-fast-implement
description: >
  Короткая реализация простого PRD_READY тикета без plan и tasklist. Используй
  только когда задача проходит Fast path gate: узкий scope, один implementation
  файл, нет открытых вопросов и пользователь явно согласовал короткий путь.
allowed-tools: Agent(implementer)
---

# AIDD Fast Implement

Используй subagent `implementer` для реализации простого тикета без создания
`plan` и `tasklist`.

Source of truth:

- `.claude/rules/core/aidd-workflow.md`, раздел `Fast path`
- `.claude/rules/core/aidd-artifacts.md`
- `.claude/rules/core/tool-usage.md`
- `.claude/rules/core/git-workflow.md`
- `.claude/rules/project/change-policy.md`
- `.claude/rules/project/naming.md`

## Назначение

`aidd-fast-implement` сокращает путь для простых defect-fix задач, где PRD уже
достаточно конкретен: известен файл, известна точная правка, закрыты вопросы и
есть проверяемые acceptance criteria.

Этот skill не предназначен для ускорения сложных задач. Если планирование
могло бы выявить существенный риск, неизвестный локальный паттерн или развилку
решения, используй обычные `aidd-plan` и `aidd-tasks`.

## Gate

Перед любыми правками основная сессия обязана проверить и кратко зафиксировать
в чате, что выполнены все условия:

- PRD существует и имеет статус `PRD_READY`.
- В PRD нет открытых `Blocking questions`, `Open questions` и нерешённых
  противоречий в scope, бизнес-правилах, формулах, данных или acceptance
  criteria.
- Пользователь явно согласовал короткий путь для текущего тикета.
- Полный diff можно описать одним предложением.
- Scope ограничен максимум одним implementation-файлом. Допускается ещё один
  тестовый, fixture или validation-файл, если PRD прямо требует его изменить.
- PRD указывает affected files, ожидаемое поведение, non-goals/constraints и
  verification.
- Нет новых mdo-объектов, реквизитов, полей, колонок, ролей, подсистем,
  обменов, публичных API, миграций данных или архитектурных решений.
- Нет удаления или переименования mdo-объектов и элементов метаданных.
- Нет необходимости в ADR, исследовании неизвестного паттерна или решении
  аналитика/бизнеса.

Если gate не пройден, остановись и верни тикет в обычный workflow:
`research`, `plan` или `tasks` по причине отказа.

## Алгоритм

1. Определи ticket id: используй переданный аргумент или
   `aidd/docs/.active_ticket`.
2. Прочитай PRD `aidd/docs/prd/<ticket>.prd.md`.
3. Прочитай `aidd/docs/feedback/<ticket>.md` и
   `aidd/docs/review/<ticket>.md`, если они существуют.
   AIDD-артефакты читай только по протоколу из
   `.claude/rules/core/aidd-artifacts.md`: точные repo-relative пути,
   `Read`/`Glob`, без `Bash`/`ls`/`dir`/`Get-ChildItem`/`Test-Path` для
   проверки наличия файлов активного тикета.
   Известные source-файлы инспектируй по `.claude/rules/core/tool-usage.md`,
   без inline shell для чтения строк, byte dumps и проверки кодировки.
4. Проверь gate из этого skill и `.claude/rules/core/aidd-workflow.md`.
5. Если gate пройден, сформулируй для `implementer` один конкретный scope:
   - ticket id;
   - ссылка на PRD;
   - affected files;
   - точное описание diff одним предложением;
   - ограничения non-goals/constraints;
   - verification и acceptance criteria.
6. Запусти один `implementer`.
   - Если задача затрагивает YAxUnit-тесты, тестовое расширение, Мокито,
     `ЮТест.Данные()`, assertions, test doubles или YAxUnit API, явно укажи
     `implementer`, что он обязан применить
     `.claude/skills/yaxunit-tests/SKILL.md`.
   - Для API YAxUnit, Мокито, HTTP-моков, `HTTPОтвет`, `HTTPСервисЗапрос` или
     `&Вместо` дополнительно укажи прочитать
     `.claude/skills/yaxunit-tests/references/api-reference.md`.
7. Проверь результат:
   - diff не выходит за scope;
   - правка соответствует PRD и constraints;
   - нет новых локальных сокращений mdo-объектов;
   - выполнены доступные проверки из PRD.
   Если `implementer` сообщил `Tooling gap`, оцени риск и зафиксируй его в PRD
   отдельным разделом `Implementation notes / Tooling gaps`, не меняя
   требования, статус, решения и acceptance criteria.
8. Не создавай и не обновляй `plan` и `tasklist`.
9. Commit делай только если пользователь просил commit или это явно требуется
   текущим рабочим сценарием. Commit message формулируй по
   `.claude/rules/core/git-workflow.md` и проектным правилам.
10. В финальном ответе укажи:
    - что тикет прошёл по `fast-implement`;
    - какие файлы изменены;
    - какие проверки выполнены;
    - если commit не делался, явно скажи это.

## Ограничения

- Не используй этот skill для feature-разработки с несколькими компонентами.
- Не используй этот skill для удаления или переименования метаданных.
- Не используй этот skill, если PRD содержит хоть один неразрешённый вопрос,
  даже если правка кажется очевидной.
- Не подменяй `feedback-fix`: замечания после пользовательского тестирования
  обрабатываются через `.claude/skills/aidd-fix-feedback/SKILL.md`.
- Основная сессия не правит project source paths напрямую; все source-правки
  выполняет `implementer`.
