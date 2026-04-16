# Тикеты, ветки и коммиты

Этот файл — project-specific настройка форматов тикетов, веток и commit
message. При переносе AIDD в другой проект меняй правила здесь, а не в
`.claude/agents` и не в `.claude/skills`.

## Настройки проекта

- Project ticket prefix: `<TICKET-PREFIX>`.
- Tracker ticket: `<TICKET-PREFIX>-<number>`.
- Work ticket: `<tracker-ticket>` или
  `<tracker-ticket>-<local-subticket>`.
- Commit ticket: `<tracker-ticket>`.
- Branch: `<branch-format>`.
- Активный commit subject format:
  `<commit-ticket>: <short-description>`

## Правила тикетов

- Любое изменение артефактов тикета, задач и коммитов должно быть привязано к
  тикету.
- Work ticket — это идентификатор задачи внутри AIDD. Он может включать
  локальный суффикс подтикета.
- Commit ticket — это идентификатор задачи для внешнего репозитория или
  трекера. Если work ticket содержит локальный суффикс подтикета, в commit
  message используй базовый tracker ticket без суффикса.
- AIDD-артефакты могут называться по work ticket.

## Ветки

- Ветки фич оформляются по настройке `Branch`.
- Если work ticket содержит локальный суффикс подтикета, ветка использует
  commit ticket без суффикса.

## Коммиты

- Коммит должен быть привязан к тикету.
- Коммит должен использовать commit ticket, а не локальный work ticket.
- Subject должен соответствовать активному `commit subject format`.
- Первая строка commit message не должна быть длиннее 50 символов целиком,
  включая ticket, служебные слова, разделители и пробелы.
- Subject должен быть понятен в удаленном репозитории без AIDD-артефактов.
- Не используй в subject номера AIDD-блоков, локальные подтикеты и служебные
  фразы вроде `Блок 2`.
- Детали change-блока выноси в body commit message.
