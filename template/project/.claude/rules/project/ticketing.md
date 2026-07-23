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

## Релизные MR

Этот раздел заполняй только если проект использует регламент создания
релизных merge request через `release-mr`. Пока в нём есть placeholders или
указан статус `disabled`, skill не должен создавать MR.

- Release MR workflow: `disabled`.
- Release branch: `<release-branch-format>`.
- Исходная ветка для переименования (если применимо):
  `<pre-release-branch-format>`.
- Целевые ветки и порядок создания MR: `<target-branches>`.
- Title: `<release-title-format>`.
- Remote и GitLab project: `<remote-name>`, `<gitlab-host>/<group>/<project>`.
- Источник состава релиза: `<git-range-and-merge-filter>`.
- Как сопоставлять feature-MR с тикетами: `<mr-ticket-matching-rule>`.
- Шаблон ссылки на трекер: `<tracker-ticket-url>` или `not-used`.
- Формат описания основного релизного MR: `<release-description-format>`.
- Assignee и reviewer: `<assignment-policy>`.

Правила:

- `release-mr` используй только после явного запроса пользователя подготовить
  или создать релизные MR.
- «Подготовить» означает собрать и показать состав/описание; публикация MR
  требует отдельного явного указания создать их, если пользователь не объединил
  оба действия в одном запросе.
- До создания MR проверь, что локальная ветка синхронизирована с remote и что
  все параметры этого раздела заполнены без placeholders.
- Не approve, не merge и не включай auto-merge. Назначения выполняй только по
  `assignment-policy`.
