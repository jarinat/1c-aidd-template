# Методика EDT MCP benchmark v1.1

## Объект измерения

Сравнивается практический workflow: Claude Code, project-local skill и один
MCP-сервер в общем EDT workspace. Фиксируются время, usage, ходы, MCP-вызовы,
качество результата, side effects и надёжность cleanup.

## Равные условия

- один открытый EDT workspace, без параллельных прогонов;
- один MCP config на CLI-сеанс через `--strict-mcp-config`;
- одинаковые model, effort, budget и max turns для одной операции;
- перед серией записаны commit/clean state `src` и версии компонентов;
- hooks отключаются только на время batch и сразу возвращаются в normal state.

`-Cold` означает новый Claude CLI-сеанс, а не гарантированно холодные EDT,
MCP process или cache. Абсолютный latency между разными машинами и проектами
не сопоставим без дополнительной нормализации.

## Write safety

Write-сценарии запускаются только с явным `-AllowFixtureWrites` и работают
исключительно с временными объектами уникального префикса. Запрещены
sync/rebuild/database/debug/tests/evaluate и XML/file fallback.

После каждого write выполняется server read-back и независимая source-проверка.
Cleanup сначала выполняется тем же сервером через typed API. При timeout
допустим только адресный recovery exact fixture paths; широкие Git reset/clean
не используются.

## Статусы

- `COMPLETE`: expected artifact подтверждён;
- `APPLIED_PARTIAL`: write применён, но final evidence не завершён;
- `QUALITY_FAIL`: артефакт не соответствует expected result;
- `UNSUPPORTED`: typed capability отсутствует;
- `INVALID_SETUP`: config/flags некорректны, run исключается;
- `FAILED`: артефакт и evidence отсутствуют.

Статус Claude-сессии сам по себе не определяет статус артефакта.

## Повтор

Для устойчивого сравнения выполни не менее трёх повторов critical операций в
перемешанном порядке. Сравнивай медианы только `COMPLETE` и quality-valid
runs, а `APPLIED_PARTIAL` сохраняй отдельно как метрику устойчивости.

Usage tokens и `total_cost_usd` — метрики Claude Code workflow; последнее есть
API-эквивалент, а не списание по подписке.
