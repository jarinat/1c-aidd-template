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
EDT-валидацию. Перед нетривиальной операцией сверяй фактическую schema через
`get_tool_guide`: состав tools зависит от версии плагина и включённых toolsets.

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
claude mcp add --scope local --transport http edt-mcp <локальный-MCP-endpoint>
```

Стабильное имя — `edt-mcp`, поэтому tools имеют префикс
`mcp__edt-mcp__*`. Endpoint бери из project-local конфигурации (например,
`.mcp.json`) или из фактической настройки EDT: он machine-specific и не должен
быть захардкожен в переносимом skill. Команда создаёт local/uncommitted
configuration. Endpoint, credentials и другие machine-specific параметры не
добавляй в `.claude/settings.json` или коммитящиеся файлы. Схемы tools,
`get_tool_guide` и `get_server_status` являются источником истины для
обязательных параметров, версии и состояния сервера.

## Обязательный workflow

1. **Discovery:** начни с `list_projects`, выбери и явно зафиксируй
   `projectName`. Пустой список может означать, что workspace/project не открыт
   в EDT, а не пустую конфигурацию. Перед визуальной проверкой формы вызови
   `get_server_status` и проверь `formRenderFlags`.
2. **Read before write:** для metadata/form/role/DCS вызови
   `get_metadata_objects` и `get_metadata_details`; для BSL — `list_modules`,
   `get_module_structure`, `read_module_source`.
3. **Минимальная typed edit:** меняй только необходимый объект/модуль через EDT
   MCP; для write передавай явный `projectName`. Для свойства metadata сначала
   запроси `get_metadata_details(assignable:true)`, если допустимые значения не
   очевидны из schema.
4. **Targeted validation:** проверяй затронутую область, а не запускай дорогую
   полную операцию по умолчанию.
5. **Evidence:** повторно прочитай объект/модуль и зафиксируй фактическую
   validation evidence и limitations.

## Capability map

### Metadata, forms, roles и DCS

Discovery: `get_metadata_objects`, `get_metadata_details`, `list_subsystems`,
`get_subsystem_content`. Typed operations: `create_metadata`,
`modify_metadata`, `adopt_metadata_object`.

`modify_metadata` покрывает не только простые свойства: проверяй его schema
для прав роли/RLS, content lists (подсистема, владельцы, движения и т. п.),
элементов формы/handlers/dynamic list, табличных макетов и основной СКД отчёта.
Для metadata/forms/roles/DCS не редактируй напрямую `*.mdo`, `*.form`,
`*.dcs`, `*.rights`, пока эта typed operation покрывает нужное изменение.
Перед правкой extension-объекта используй `adopt_metadata_object`, если это
требует EDT. Для формы используй structural evidence; визуальный evidence
дают `get_form_layout_snapshot` и `get_form_screenshot` только при включённых
renderer flags. Для табличного макета применяй `get_template_screenshot` — он
не зависит от form renderer flags.

### BSL modules and methods

Discovery: `list_modules`, `get_module_structure`, `read_method_source`,
`go_to_definition`, `get_symbol_info`. Обязательная запись:
`read_module_source` → сохранить `contentHash` → `write_module_source` с
`expectedHash`. Предпочитай минимальный `searchReplace` с точным `oldSource`;
для полной замены передавай также `expectedSource`. При mismatch перечитай
модуль, пересобери минимальную правку и повтори; не форсируй stale write.

### References, queries и validation

- `find_references`, `get_method_call_hierarchy`, `go_to_definition` — semantic
  references/callers/callees/definition; `get_content_assist` — контекстные
  предложения; `search_in_code` — literal fallback.
- `validate_query` — проверка запросов.
- `get_project_errors`, `get_problem_summary`, `revalidate_objects` — markers
  и targeted validation.
- `clean_project` — дорогая полная DISK→MODEL revalidation; может отбросить
  несохранённые model edits, поэтому не используй её рутинно.

### YAxUnit, debug и database operations

`run_yaxunit_tests`, debug/profiling tools и `update_database` выполняй только
в основной сессии и по решению пользователя. При тестах применяй
`yaxunit-tests`.
У `run_yaxunit_tests` значение `updateBeforeLaunch=true` по умолчанию: оно
может пересчитать проект, завершить запущенный EDT-клиент и молча обновить ИБ.
Не запускай его без явного решения пользователя на эти последствия; при
разрешении тестов без обновления ИБ передавай `updateBeforeLaunch:false` и
зафиксируй риск platform dialog/stale configuration.

`update_database` меняет ИБ и имеет native preview/confirm: сначала вызов без
`confirm`, затем `confirm:true` только по решению пользователя. Для debug
`evaluate_expression` и `set_variable` выполняют BSL в живом приложении;
считай их side-effect операциями, а не безопасным чтением.

## Destructive operations

`delete_metadata`, `rename_metadata_object`, `update_database`,
`delete_project`, `delete_infobase` и `delete_launch_config` имеют двухфазный
workflow: сначала preview без `confirm`, потом явный `confirm=true` только по
решению пользователя. Перед удалением metadata применяй
`1c-metadata-removal-impact`; `USED`/`UNCLEAR` точки без решения не удаляй.

`resync_to_disk` пишет модель EDT на диск: его обычный режим может
восстанавливать отсутствующие `.mdo`, `fullExport:true` перезаписывает все
дисковые объекты только вместе с `overwriteDiskEdits:true`, а
`cleanDanglingReferences:true` удаляет висячие ссылки из `Configuration.mdo`.
Не используй его как routine validation. `clean_project` действует в обратную
сторону (DISK→MODEL) и отбрасывает несохранённые model edits.

## Known limitations

- Form screenshot/layout зависит от EDT renderer flags и может быть пустым;
  проверь `get_server_status.formRenderFlags`, используй structural evidence и
  зафиксируй limitation.
- Markers могут быть stale; для изменённого FQN предпочитай
  `revalidate_objects`.
- `clean_project` и `update_database` дороги.
- `get_check_description` требует настроенную папку описаний checks; без неё
  фиксируй configuration limitation, а не трактуй ответ как отсутствие check.
- При включённом progressive disclosure используй `list_toolsets` и
  `enable_toolset`, затем повторный `tools/list`; не предполагай, что скрытый
  tool отсутствует на сервере.
- При отсутствующей typed operation или подтверждённом ограничении зафиксируй
  literal evidence и переходи к A-RSV или B по tool-usage policy.

## Формат evidence

```text
MCP edt-mcp:
- project: <projectName>
- server: <plugin/EDT version, relevant renderer/toolset state>
- discovery: <list_projects, metadata/module/reference tools>
- edits: <typed metadata operation / write_module_source expectedHash>
- validation: <validate_query, project errors, revalidate_objects, YAxUnit>
- limitations: <project absent, renderer disabled, stale marker, unsupported op>
```
