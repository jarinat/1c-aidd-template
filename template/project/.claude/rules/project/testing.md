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
  - `<runner-name>`:
    - Command/script:
    - Когда использовать:
    - PASS criteria:
    - Allowed changes:
    - Required diagnostics:
    - Limits override:
- По умолчанию не запускай тесты, smoke, HTTP-запросы, build/update scripts,
  внешние сервисы, БД или MCP/log диагностику, если конкретный runner не
  описан здесь, в PRD/plan/tasklist/debug-задании или явно не задан
  пользователем.
- Предпочитай project-local scripts из `.claude/scripts/*` для повторяемых
  debug runners. Скрипт должен иметь понятный exit code и машинно читаемый
  output, например JSON.
- Не храни URL с секретами, пароли, токены, строки подключения, IIS paths и
  machine-specific настройки в переносимом runtime-слое.
- MCP/БД/журнал регистрации можно использовать только как read-only источник
  диагностики, если доступ и границы явно описаны в project-specific правилах
  или test/debug plan.

## Ограничения

- <project-specific-testing-constraint>
