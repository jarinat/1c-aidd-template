# Правила тестирования

Этот файл — project-specific source of truth по тестам и проверкам.

## Доступные виды проверок

- Unit tests:
- Integration tests:
- Smoke tests:
- Manual checks:
- Static checks:

## Когда нужны тесты

- Добавляй или обновляй тесты при изменении бизнес-логики, форматов данных,
  интеграций, запросов, движений, прав или метаданных.
- Если тесты невозможны или слишком дороги, зафиксируй причину и предложи
  ручную проверку.

## Команды проверки

- Основная команда:
- Дополнительные команды:

## Debug automation policy

Этот раздел описывает project-specific разрешения для автономного
`aidd-debug-loop`.

- Debug runners:
  - `http-smoke`:
    - Command/script: `.claude/scripts/http-smoke.cmd`.
    - Когда использовать: HTTP API / HTTPService проверки, если PRD, plan,
      tasklist или `aidd/docs/debug/<ticket>.md` явно задают test plan.
    - Config: `.claude/config/http-smoke.local.json` (machine-local, не
      коммитится) или `-ConfigFile`; пример профилей —
      `.claude/config/http-smoke.example.json`.
    - PASS criteria: ожидаемый HTTP status и, при необходимости,
      expected substring из test plan.
    - Allowed changes: только зона, явно указанная в debug artifact.
    - Required diagnostics: structured JSON output runner-а и запись
      результата в `aidd/docs/debug/<ticket>.md`.
    - Limits override: только если задано в debug artifact или пользователем.
- По умолчанию не запускай тесты, smoke, HTTP-запросы, build/update scripts,
  внешние сервисы, БД или MCP/log диагностику, если конкретный runner не
  описан здесь, в PRD/plan/tasklist/debug-задании или явно не задан
  пользователем.
- Предпочитай project-local scripts из `.claude/scripts/*` для повторяемых
  debug runners. Скрипт должен иметь понятный exit code и машинно читаемый
  output, например JSON.
- Не храни URL с секретами, пароли, токены, строки подключения, IIS paths и
  machine-specific настройки в переносимом runtime-слое.
- Для HTTP-smoke не храни секреты в JSON-конфиге. В config допустимы
  `usernameEnv` / `passwordEnv`; сами значения задаются локально через env
  vars. URL локальных стендов и публикаций указывай в
  `.claude/config/http-smoke.local.json`, а не в переносимом example.
- Test fixtures для HTTP-smoke размещай в `aidd/fixtures/<ticket>/`.
  Для idempotent/pass сценариев используй `{{TIMESTAMP}}` в payload, если
  нужен уникальный внешний идентификатор.
- MCP/БД/журнал регистрации можно использовать только как read-only источник
  диагностики, если доступ и границы явно описаны в project-specific правилах
  или test/debug plan.

## Ограничения

- <project-specific-testing-constraint>
