---
name: 1c-edt-companion-mcp-tools
description: >
  Основной EDT MCP-слой для discovery, typed-редактирования и validation
  1С/EDT-проектов. Используй, когда доступны mcp__edt-companion-mcp__*.
---

# 1c-edt-companion-mcp-tools

`edt-companion-mcp` работает внутри открытого 1С:EDT workspace. Это default
EDT-слой проекта при доступных `mcp__edt-companion-mcp__*`; `edt-mcp` —
резервный EDT-слой, `1c-rsv` — следующий fallback. Endpoint, credentials и
machine-specific MCP configuration держи локально и не коммить.

## Runtime contract

Не считай этот файл или README сервера API-контрактом. В начале работы с
сервером вызови `tools/list`, а перед редкой или рискованной операцией сверяй
фактические inputSchema, required-поля, enum и output. Runtime schema имеет
приоритет над памятью и Markdown-документацией.

Минимальная подтверждённая версия плагина — v0.1.4. После обновления, которое
требует новые EDT bundles, пользователь перезапускает EDT с `-clean`.
`show_edt_version` и `list_workspace_projects` используй для фиксации
версии, открытого workspace и точного `projectName`; не угадывай имена.

## Routing и границы fallback

| Режим | Условие | Действие |
| --- | --- | --- |
| A-COMP | доступны `mcp__edt-companion-mcp__*` | этот skill — default |
| A-EDT | companion недоступен, не покрывает операцию, вернул ошибку или не подтверждает результат | `1c-edt-mcp-tools` |
| A-RSV | оба EDT MCP недоступны либо нужен подтверждённо уникальный read-only capability RSV | `1c-rsv-tools` |
| B | структурированный слой недоступен | project fallback; это не tooling gap само по себе |

Не смешивай write API `edt-companion-mcp`, `edt-mcp` и `1c-rsv` внутри
одного change block над одним объектом или BSL-модулем. Перед fallback:

1. Заверши или явно отмени dirty buffer companion; `save=false` не виден
   другому серверу и файловым инструментам.
2. Перечитай фактическое состояние уже целевым сервером.
3. Передай ему целую следующую операцию, а не часть прежней правки.
4. Зафиксируй наблюдение A-COMP по правилам artifacts.

## Рабочий цикл

1. Discovery: `list_workspace_projects` → точный `projectName`; затем
   узкие list/get/read tools. Для BSL сначала `list_modules` /
   `get_module_structure`, потом `read_method_source` или узкое чтение.
2. До write перечитай объект, форму или модуль. Для спорной операции сначала
   используй `dryRun=true`, если это предусмотрено schema.
3. Предпочитай `edit_metadata` для metadata, форм, СКД, ролей и
   заимствования; `edit_xdto_package` для XDTO; `write_module_source` для
   BSL. Не правь соответствующие EDT XML напрямую, пока typed операция есть.
4. После write перечитай затронутую область и выполни узкую validation:
   `get_validation_errors` по объекту, `validate_query` для синтаксиса
   запроса, другую согласованную проверку.

`validate_query` не доказывает семантическую связь запроса с метаданными.
`get_validation_errors` и `rebuild_project` могут использовать разные
наборы маркеров. Не объявляй project-wide legacy markers регрессией текущей
правки без сравнения с baseline.

## Operations с повышенным риском

Только основная сессия и только по явному решению пользователя запускает
`rebuild_project`, `sync_database`, `run_yaxunit` и debug tools. Для
удаления metadata сначала примени `1c-metadata-removal-impact`; не используй
`force` без явного решения. Для полного rebuild/обновления ИБ сначала
используй доступный read-only preview (`dryRun` / `checkOnly`).

## Известные ограничения

- Не применяй `list_modules kindFilter=commonModule`: известен пустой
  результат. Получи список без фильтра и отфильтруй по фактическому `kind`.
- `addTemplate` с `templateType=BinaryData` не записывает бинарное
  `Template.bin`; это capability gap, а не повод молча считать metadata
  полноценным бинарным макетом.
- Extension support проверяй по конкретному tool: list-инструменты могут
  работать, когда отдельный details tool не принимает extension project.
- `write_module_source searchReplace` должен задавать `expectMatches`.
  Если literal match не подтверждён, не повторяй write вслепую: перечитай
  фрагмент и выбери узкий безопасный режим.

## Evidence A-COMP

Если companion дал ошибку, неполный результат, schema/documentation drift,
неудобный workflow, заметную деградацию или идею улучшения, зафиксируй это в
артефактах текущего тикета по
`.claude/rules/core/aidd-artifacts.md`, даже если fallback успешно завершил
работу. Не создавай внешний GitHub issue без явной команды пользователя.

Минимальная запись:

```text
A-COMP observation:
- class: bug | documentation-drift | capability-gap | enhancement | performance
- plugin/EDT: <версии из runtime>
- tool/schema: <tool, важные args и фактическая schema>
- operation/evidence: <ожидание, ответ/ошибка, воспроизводимость>
- impact: <на что влияет>
- fallback/decision: <что применено или почему не нужен>
```
