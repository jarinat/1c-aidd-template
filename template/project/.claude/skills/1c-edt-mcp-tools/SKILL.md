---
name: 1c-edt-mcp-tools
description: >
  Бесплатный EDT MCP для discovery, типизированного редактирования и валидации
  1С/EDT-конфигураций. Используй как предпочтительный A-EDT слой для metadata,
  форм, ролей, СКД, BSL, запросов и EDT-проверок, если доступен edt-mcp.
---

# 1c-edt-mcp-tools

Это source of truth для бесплатного MCP-сервера `edt-mcp` (режим A-EDT). Он
предоставляет структурный discovery, типизированные EDT-операции и
EDT-валидацию.

- **A-EDT:** если доступны `mcp__edt-mcp__*`, используй этот skill.
- **A-RSV:** если EDT MCP недоступен, но доступны `mcp__1c-rsv__*`, используй
  `.claude/skills/1c-rsv-tools/SKILL.md`.
- **B:** если недоступны оба MCP, используй штатный project fallback. Само по
  себе отсутствие обоих MCP не является `Tooling gap`.

Если доступен только один MCP, используй его. `1c-rsv` остаётся поддерживаемой
альтернативой, особенно для его уникальных read-only возможностей. Не смешивай
write API `edt-mcp` и `1c-rsv` в одном change block для одного объекта или
модуля.

## Локальное подключение

```text
claude mcp add --scope local --transport http edt-mcp http://host.docker.internal:8765/mcp
```

Стабильное имя — `edt-mcp`, поэтому tools имеют префикс
`mcp__edt-mcp__*`. Команда создаёт local/uncommitted configuration. Endpoint,
credentials и другие machine-specific параметры не добавляй в
`.claude/settings.json` или коммитящиеся файлы. Схемы tools и `get_tool_guide`
являются источником истины для обязательных параметров и поведения операций.

## Обязательный workflow

1. **Discovery:** начни с `list_projects`, выбери и явно зафиксируй
   `projectName`. Пустой список может означать, что workspace/project не открыт
   в EDT, а не пустую конфигурацию.
2. **Read before write:** для metadata/form/role/DCS вызови
   `get_metadata_objects` и `get_metadata_details`; для BSL — `list_modules`,
   `get_module_structure`, `read_module_source`.
3. **Минимальная typed edit:** меняй только необходимый объект/модуль через EDT
   MCP; для write передавай явный `projectName`.
4. **Targeted validation:** проверяй затронутую область, а не запускай дорогую
   полную операцию по умолчанию.
5. **Evidence:** повторно прочитай объект/модуль и зафиксируй фактическую
   validation evidence и limitations.

## Capability map

### Metadata, forms, roles и DCS

Discovery: `get_metadata_objects`, `get_metadata_details`, `list_subsystems`,
`get_subsystem_content`. Typed operations: `create_metadata`,
`modify_metadata`, `adopt_metadata_object`. Для metadata/forms/roles/DCS не
редактируй напрямую `*.mdo`, `*.form`, `*.dcs`, `*.rights`, пока EDT MCP
покрывает операцию. Перед правкой extension-объекта используй
`adopt_metadata_object`, если это требует EDT.

### BSL modules and methods

Discovery: `list_modules`, `get_module_structure`, `read_method_source`,
`go_to_definition`, `get_symbol_info`. Обязательная запись:
`read_module_source` → сохранить `contentHash` → `write_module_source` с
`expectedHash`. При mismatch перечитай модуль, пересобери минимальную правку и
повтори; не форсируй stale write.

### References, queries и validation

- `find_references`, `get_method_call_hierarchy`, `go_to_definition` — semantic
  references/callers/callees/definition; `search_in_code` — literal fallback.
- `validate_query` — проверка запросов.
- `get_project_errors`, `get_problem_summary`, `revalidate_objects` — markers
  и targeted validation.
- `clean_project` — дорогая полная DISK→MODEL revalidation; может отбросить
  несохранённые model edits, поэтому не используй её рутинно.

### YAxUnit, debug и database operations

`run_yaxunit_tests`, debug tools и `update_database` выполняет только основная
сессия по решению пользователя. При тестах применяй `yaxunit-tests`.
`update_database` меняет ИБ и требует native preview/confirm.

## Destructive operations

`delete_metadata`, `rename_metadata_object`, `update_database`,
`delete_project`, `delete_infobase` и `delete_launch_config` имеют двухфазный
workflow: сначала preview без `confirm`, потом явный `confirm=true` только по
решению пользователя. Перед удалением metadata применяй
`1c-metadata-removal-impact`; `USED`/`UNCLEAR` точки без решения не удаляй.

## Known limitations

- Form screenshot/layout зависит от EDT renderer flags и может быть пустым;
  используй structural evidence и зафиксируй limitation.
- Markers могут быть stale; для изменённого FQN предпочитай
  `revalidate_objects`.
- `clean_project` и `update_database` дороги.
- При отсутствующей typed operation или подтверждённом ограничении зафиксируй
  literal evidence и переходи к A-RSV или B по tool-usage policy.

## Формат evidence

```text
MCP edt-mcp:
- project: <projectName>
- discovery: <list_projects, metadata/module/reference tools>
- edits: <typed metadata operation / write_module_source expectedHash>
- validation: <validate_query, project errors, revalidate_objects, YAxUnit>
- limitations: <project absent, renderer disabled, stale marker, unsupported op>
```
