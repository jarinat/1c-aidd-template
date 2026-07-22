# EDT MCP benchmark kit

Переносимый набор для сравнения `edt-companion-mcp`, `edt-mcp` и `1c-rsv` в
одном 1С:EDT workspace. В нём нет endpoint-ов, путей, имён рабочих проектов
и raw-логов: они всегда machine- и project-specific и не должны попадать в Git.

Состав:

- `METHODOLOGY.md` — условия корректного сравнения;
- `scenario-catalog.md` — полный каталог read/write операций;
- `reports/baseline-2026-07-22.md` — обезличенный итог первой серии;
- `baselines/write-suite-2026-07-22.csv` — значения этой серии для будущего
  машинного сопоставления.

## Использование в новом проекте

1. Скопируй исполняемый harness в `aidd/local/mcp-benchmark` нового проекта.
2. Создай `configs/*.json` локально из фактических MCP endpoint-ов; не
   коммить их.
3. Адаптируй FQN и fixture names в сценариях под проект.
4. Зафиксируй версии Claude Code, EDT и MCP-плагинов.
5. Выполни baseline и сохрани raw results только в `aidd/local/`.
6. Сравнивай новый run с CSV только при совпадающих версии методики и
   сценариях.

Этот kit измеряет workflow Claude Code + skill + MCP. Он не является чистым
benchmark latency самого MCP-сервера.
