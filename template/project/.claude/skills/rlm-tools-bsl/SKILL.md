---
name: rlm-tools-bsl
description: >
  Read-only исследование больших 1С/EDT/BSL кодовых баз через MCP-сервер
  rlm-tools-bsl. Используй как ускоритель discovery/research/review, когда
  нужно найти объекты метаданных, методы, формы, ссылки, движения, подписки,
  интеграции или локальные reference patterns в большой конфигурации.
---

# rlm-tools-bsl

Используй этот skill только как навигационный и аналитический слой поверх
исходников 1С. Результаты MCP helpers помогают быстро сузить область поиска, но
не заменяют чтение конкретных файлов, методов, XML-метаданных и AIDD-артефактов.

## Когда использовать

- Исследование крупной EDT/CF-кодовой базы на этапе `research`.
- Предварительное technical reconnaissance перед PRD, если нужно понять текущую
  реализацию.
- Review изменений, когда нужно проверить зависимости, callers, reference
  pattern или риск регрессии за пределами diff.
- Поиск объектов по бизнес-названию, синониму, области, заголовку модуля или
  имени метода.
- Анализ метаданных: реквизиты, табличные части, измерения, ресурсы,
  предопределенные элементы, формы, роли.
- Трассировка поведения: подписки на события, движения регистров, ввод на
  основании, печатные формы, функциональные опции.
- Интеграции: HTTP-сервисы, web-сервисы, XDTO-пакеты, планы обмена.
- Расширения: поиск перехватов `&Вместо`, `&Перед`, `&После` и nearby
  extensions.

## Когда не использовать

- Для маленького точечного чтения известного файла, где достаточно `Read`.
- Как единственный источник истины для финального вывода.
- Для автоматического изменения индекса, реестра проектов или системной службы
  без явного согласия пользователя.
- Для вывода требований из похожей реализации: reference pattern остается
  инженерным аналогом, а не источником scope.

## Доступные MCP tools

Ожидаемый user-level MCP server:

```json
{
  "mcpServers": {
    "rlm-tools-bsl": {
      "type": "http",
      "url": "http://127.0.0.1:9000/mcp"
    }
  }
}
```

Основные tools:

- `rlm_projects` — список и управление реестром проектов.
- `rlm_start` — старт read-only сессии анализа по `project` или `path`.
- `rlm_execute` — выполнение Python-кода внутри сессии с BSL helpers.
- `rlm_end` — завершение сессии.
- `rlm_index` — управление индексом. Используй `info` свободно, а
  `build`, `update`, `drop` только после явного согласия пользователя.

## Базовый workflow

1. Если пользователь назвал проект, сначала попробуй проектный alias:
   `rlm_projects(action="list")`, затем `rlm_start(project="<name>", ...)`.
2. Если alias не найден, используй абсолютный `path` только если он уже известен
   из project rules, AIDD-артефактов или явного сообщения пользователя.
3. Для больших конфигураций сначала проверь индекс через
   `rlm_index(action="info", project="<name>")` или поле `index` в ответе
   `rlm_start`.
4. В `rlm_execute` группируй связанные действия в один батч:
   поиск -> чтение top matches -> извлечение процедур/метаданных -> краткий
   summary.
5. После MCP discovery прочитай подтверждающие исходники обычными инструментами
   текущей роли (`Read`, `Glob`, `Grep`) или через read-only helpers, если они
   разрешены сценарием.
6. В research/review явно отделяй:
   - факты из исходников;
   - результаты MCP helpers;
   - выводы;
   - ограничения проверки.
7. Всегда заверши сессию через `rlm_end(session_id)`, если она больше не нужна.

## Полезные helpers внутри `rlm_execute`

Discovery:

- `search(query, scope="all", limit=30)`
- `search_methods(query, limit=30)`
- `search_objects(query)`
- `search_regions(query, limit=200)`
- `search_module_headers(query, limit=200)`
- `find_module(name)`
- `find_by_type(category, name="")`

Код:

- `extract_procedures(path)`
- `find_exports(path)`
- `read_procedure(path, proc_name, include_overrides=False)`
- `find_callers_context(proc, hint, offset, limit)`
- `safe_grep(pattern, hint, max_files=20)`
- `extract_queries(path)`
- `code_metrics(path)`

Метаданные и формы:

- `parse_object_xml(path)`
- `parse_form(object_name, form_name="", handler="")`
- `find_attributes(name="", object_name="", category="", kind="", limit=500)`
- `find_predefined(name="", object_name="", limit=500)`
- `find_enum_values(enum_name)`
- `find_references_to_object(object_ref, kinds=None, limit=1000)`
- `find_defined_types(name)`

Бизнес-поведение:

- `analyze_object(name)`
- `analyze_document_flow(doc_name)`
- `analyze_subsystem(name)`
- `find_custom_modifications(obj, custom_prefixes=None)`
- `find_event_subscriptions(obj, custom_only=False)`
- `find_register_movements(doc_name)`
- `find_register_writers(reg_name)`
- `find_based_on_documents(doc_name)`
- `find_print_forms(obj_name)`
- `find_functional_options(obj_name)`
- `find_roles(obj_name)`

Интеграции и расширения:

- `find_http_services(name="")`
- `find_web_services(name="")`
- `find_xdto_packages(name="")`
- `find_exchange_plan_content(name)`
- `detect_extensions()`
- `get_overrides(object_name="", method_name="")`
- `find_ext_overrides(ext_path, obj="")`

Навигация:

- `help(task="")`
- `get_index_info()`
- `read_file(path)`
- `read_files(paths)`
- `grep(pattern, path=".")`
- `grep_summary(pattern, path=".")`
- `grep_read(pattern, path=".", max_files=10, context_lines=0)`
- `glob_files(pattern)`
- `tree(path=".", max_depth=3)`
- `find_files(name)`

## Правила безопасности и качества

- Не выполняй `rlm_projects(add/remove/rename/update)` без явной просьбы
  пользователя и пароля.
- Не выполняй `rlm_index(build/update/drop)` без явного согласия пользователя:
  эти команды меняют локальный cache/index и могут быть долгими.
- Если индекс отсутствует или устарел, зафиксируй это как ограничение. Не
  заявляй полноту call graph, FTS, synonyms или metadata references.
- Для broad search по большим конфигурациям предпочитай `find_module`,
  `search_*`, `find_references_to_object` и специализированные helpers вместо
  широкого `grep` по всему дереву.
- Не используй результаты `analyze_*` как самостоятельное доказательство.
  Подтверждай критичные выводы конкретными файлами, методами или XML-узлами.
- Если helper вернул слишком широкий или неоднозначный результат, сузь запрос
  через тип метаданных, имя объекта, подсистему, модуль или локальный hint.
- Для YAxUnit, запросов 1С, EDT-форм и удаления метаданных применяй
  соответствующие специализированные skills; этот skill их не заменяет.

## Формат фиксации в research/review

Когда rlm-tools-bsl повлиял на вывод, фиксируй коротко:

```text
MCP rlm-tools-bsl:
- project/path: <alias or path>
- index: loaded=<true|false>, has_fts=<true|false>, warnings=<...>
- helpers: <helper names>
- confirmed by source: <files/methods/XML>
- limitations: <missing index / partial scan / ambiguous results>
```
