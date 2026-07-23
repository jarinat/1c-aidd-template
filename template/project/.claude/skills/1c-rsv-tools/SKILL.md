---
name: 1c-rsv-tools
description: >
  Discovery, валидация и редактирование 1С/EDT-конфигурации через MCP-сервер
  1c-rsv (плагин 1С:EDT). Используй только если `1c-rsv` — единственный
  выбранный EDT MCP в project-local .mcp.json.
---

# 1c-rsv-tools

> Применяй этот skill, только если в project-local `.mcp.json` среди
> `edt-companion-mcp`, `edt-mcp`, `1c-rsv` указан ровно один сервер — `1c-rsv`.
> Если он недоступен или не покрывает операцию, не переключайся на другой EDT
> MCP: зафиксируй limitation/tooling gap и используй штатный project fallback.

Этот skill описывает правила использования MCP-сервера `1c-rsv`. Сервер
работает поверх запущенного 1С:EDT (HTTP MCP) и даёт структурный discovery,
валидацию EDT и write-операции через штатные модели EDT, а не через прямую
правку XML/BSL-файлов.

Актуальная база правил проверена на MCP:RSV Server 7.1.0. Реестр tools зависит
от выбранного профиля и установленных компонентов: перед редкой операцией
сверяй фактический `tools/list`, затем читай `operation=help`. Не переноси
предположения о составе tools или operations из старых версий сервера.

## Когда использовать

- Discovery 1С/EDT-кодовой базы: метаданные, BSL-модули, методы, формы,
  ссылки между объектами, иерархия вызовов, callers, СКД и локальные patterns.
- Любое создание, переименование, удаление или изменение объектов метаданных,
  реквизитов, табличных частей, форм, команд, ролей, подсистем, HTTP-сервисов,
  XDTO, предопределённых элементов, СКД, макетов и расширений.
- Любое редактирование BSL-модулей через `write_module_source`.
- Валидация EDT-маркеров после правок, если встроенной валидации записи
  недостаточно или нужно проверить объект/проект шире.
- Чтение реальной структуры формы и динамических списков.
- Запуск YAxUnit, Vanessa Automation, обновления ИБ, clean build и debug
  session - только из основной сессии и только при явном решении пользователя.

## Когда не использовать

- Для маленького точечного чтения известного файла, где достаточно `Read`.
- Для прямой правки `*.mdo`, `*.form`, `*.dcs`, `*.rights` или `*.bsl` через
  `Write`/`Edit`, если есть соответствующий MCP-инструмент.
- Для генерации GUID/UUID при штатном MCP-пути: `edit_metadata` сам управляет
  идентификаторами. `.claude/scripts/new-guid.cmd` допустим только для явно
  разрешённого XML fallback.
- Для MR review в отдельном worktree, если MCP привязан к другому EDT
  workspace. В таком сценарии используй правила review-agent-а.

## Доступные инструменты

### Workspace и EDT info

- `list_workspace_projects` - проекты EDT workspace. По умолчанию
  `onlyV8Projects=true`; для DT-проектов внешних обработок/отчётов возвращает
  `externalObjects`.
- `list_applications` - Run Configurations/ИБ проекта.
- `show_edt_version` - версия EDT и Java/OS окружение.
- `get_config_properties` - свойства конфигурации, подсистемы, статистика.

### Discovery: метаданные, код, формы

- `list_metadata_objects` - каталог объектов всех основных типов 1С, включая
  расширения и DT-проекты внешних обработок/отчётов; используй `nameMask`,
  `objectType`, `offset`, `limit`.
- `get_object_details` - структура объекта, свойства, формы, команды, модули,
  измерения/ресурсы, DCS. Для свойств включай `includeProperties=true`; для
  больших СКД используй DCS-пагинацию.
- `get_object_help` - синоним, подсистемы, комментарий MDO и HTML-help.
- `list_modules` - каталог BSL-модулей с фильтрами и `compact=true`.
- `code_structure` - основной инструмент чтения BSL:
  `outline`, `readMethod`, `readModule`, `find`, `help`.
- `code_search` - поиск по проекту/связанным проектам:
  `textSearch`, `objectReferences`, `methodReferences`, `resolveSymbol`,
  `callHierarchy`, `dcsSearch`, `open`, `help`. `open` только показывает
  объект, форму, метод или строку в EDT для человека и не изменяет исходники.
- `get_form_image` - `format=structure` для дерева формы, командных панелей,
  кнопок, `commandName`, layout-полей; `listQuery` читает полный запрос
  динамического списка с пагинацией.
- `ai_context` - агрегированный контекст по объекту, форме, модулю или методу.
- `get_platform_docs` - справочник платформы 1С: API, BSL, язык запросов, СКД.

Старые tools `get_module_structure`, `read_module_source`,
`read_method_source` не использовать: их заменяет
`code_structure`.

### Валидация и diff

- `validate_query` - штатный EDT-валидатор языка запросов. С `projectName` и
  `projectScope=true` проверяет не только синтаксис, но и таблицы, поля,
  разыменование, группировки, виртуальные таблицы и типы. Без проектного
  scope config-dependent диагностики не считай окончательной истиной.
- `get_validation_errors` - EDT/Eclipse-маркеры и официальные quick fixes.
  `action=read|applyQuickFix`, `scope=session|object|project|all`,
  `severity=ERROR|WARNING|INFO|ALL`, `source=edt|eclipse|all`,
  `fileFilter`, `checkIdFull`, `suppressionHint`, `quickFixVariants`.
- `code_review` - read-only ревью BSL модуля, метода, диапазона строк или
  проекта по диагностике BSL Language Server. Это не замена `git diff` и не
  компиляционная валидация. Инструмент может потребовать отдельный компонент
  MCP:RSV Code Review; при его отсутствии зафиксируй ограничение без fallback
  к выдуманным диагностическим правилам.

### Edit через EDT API

- `edit_metadata` - единый конструктор операций по метаданным, формам, СКД,
  макетам, расширениям, HTTP-сервисам, XDTO, ролям и внешним объектам.
  Перед редкой операцией читай `edit_metadata operation=help topic=<...>`.
- `write_module_source` - запись BSL: `replace`, `append`, `insertBefore`,
  `insertAfter`, `replaceLines`, `replaceMethod`, пакетная замена
  `methods=[{methodName, source}, ...]`. В 7.1.0 первый вызов по умолчанию
  выполняется как `dryRun=true`; для реальной записи требуется осознанно
  передать `dryRun=false`.
- `export_object` - экспорт DT-проектов внешних обработок/отчётов в
  `.epf`/`.erf`.

Полезные overview topics `edit_metadata`: `workflow`, `extensionsWorkflow`,
`externalObjectsWorkflow`, `dcsWorkflow`, `dcsTroubleshooting`,
`formsTroubleshooting`, `registersWorkflow`, `matrixWorkflow`,
`composerWorkflow`, `createObjectHttpService`, `createObjectEventSubscription`,
`types`, `objectTypes`, `formTypes`, `propertyValues`, `supportLock`.

### Build, БД, тесты, отладка и диагностика

Эти tools действуют на ИБ, процесс EDT или внешнее окружение. Не вызывай их
из subagent. Основная сессия вызывает их только при явном решении пользователя.

- `rebuild_project` - clean build EDT-проекта; требует `confirmed=true`.
- `sync_database` - обновление ИБ из EDT; `fullReload=true` только как
  аварийный режим.
- `yaxunit_tests` - unit/API тесты YAxUnit, режимы `run|debug`.
- `vanessa` - UI/BDD тесты Vanessa Automation:
  `run`, `checkSyntax`, `steps`, `setup`, `help`.
- `launch_debugger` - запуск/управление debug-сессией, breakpoints,
  переменные, evaluate.
- `diagnostics` - замер производительности, технологический журнал и журнал
  регистрации. Может включать техжурнал, работать с ИБ и создавать заметную
  нагрузку; вызывай только из основной сессии и только по явному решению
  пользователя.

## Базовый workflow

1. Зафиксируй `projectName` через `list_workspace_projects` или явное указание
   пользователя/AIDD-артефактов. Для write-операций всегда передавай
   `projectName` явно.
2. Для discovery начинай с узких структурных запросов:
   - объект: `list_metadata_objects` -> `get_object_details`;
   - модуль: `list_modules` -> `code_structure outline|find|readMethod`;
   - ссылки: `code_search objectReferences|methodReferences|callHierarchy`;
   - СКД: `get_object_details dcsInclude=...` или `code_search dcsSearch`;
   - форма: `get_form_image format=structure` или `ai_context`.
3. Для чтения BSL предпочитай `code_structure`:
   - `outline` - карта модуля без тел;
   - `find` - поиск внутри одного модуля, с `linesContext` или
     `expandToMethod`;
   - `readMethod` - тело конкретного метода;
   - `readModule` - только когда нужен весь модуль или диапазон.
   Номера строк в ответах абсолютные и напрямую подходят для
   `write_module_source`.
4. Для поиска по всей базе используй `code_search`. Без `projectName` он умеет
   auto-scope по основной конфигурации и зависимым расширениям/внешним
   объектам; при явном `projectName` расширяй scope через
   `searchAllProjects=true`, если нужны linked-проекты.
5. Для редактирования метаданных, форм, СКД и ролей используй
   `edit_metadata`, а не прямую правку XML. Сначала изучи help нужной
   операции или профильного workflow topic.
6. Для редактирования BSL используй `write_module_source`.
   - Сначала выполни безопасный preview (`dryRun=true`, это default 7.1.0) и
     сверь target/diff с намерением задачи.
   - Только затем повтори тот же вызов с `dryRun=false` для реальной записи.
   - Для изменения одного метода - `replaceMethod`.
   - Для нескольких методов - `methods=[...]`, чтобы записать файл и
     провалидировать один раз.
   - Для кода вне методов - `replaceLines` с обязательным
     `expectedFirstLine`; для insert - указывай `expectedLine`.
   - `replace` всего модуля только при явном основании и
     `confirmFullReplace=true`.
7. После реальной записи BSL читай `validation` из ответа
   `write_module_source`: отдельный `get_validation_errors` обычно не нужен.
   Для серии правок можно поставить `validateAfterWrite=false` и вызвать
   `get_validation_errors scope=session waitForValidation=true` один раз.
8. Не используй `scope=project` в крупных типовых конфигурациях без причины:
   там много legacy-маркеров, не связанных с текущей задачей.
9. Не вызывай `sync_database`, `rebuild_project`, `yaxunit_tests`,
   `vanessa` или `launch_debugger` из subagent.

## Чтение ответов и fallback

- Для `edit_metadata` авторитетный признак успешной записи -
  `success:true` вместе с полями результата (`applied`, `created`,
  `renamed`, `removed` и т.п.). Не считай операцию неуспешной только из-за
  блока синхронизации экспорта, если нет явной ошибки.
- `exportSync` описывает запись EDT на диск. `forceExportOk:false` само по
  себе не доказывает, что изменение не применилось: сначала проверь фактическое
  состояние через `get_object_details`, `get_form_image` или `code_structure`.
- Перед XML/BSL fallback выполни чеклист:
  1. зафиксируй буквальный ответ MCP с `success:false`, `supportLock`,
     `typeWarning`, ошибкой валидации или иной конкретной причиной;
  2. проверь фактическое состояние структурным read-инструментом;
  3. прочитай `edit_metadata operation=help topic=<operation>` или профильный
     workflow/troubleshooting topic;
  4. зафиксируй `Tooling gap` с буквальным ответом инструмента;
  5. прими fallback-решение по `.claude/rules/core/tool-usage.md`.
- Если fallback меняет scope, риск или смысл согласованной работы, спроси
  пользователя перед правкой.

## Правила безопасности и качества

- Не редактируй напрямую `*.mdo`, `*.form`, `*.dcs`, `*.rights`, `*.bsl`,
  если MCP покрывает операцию.
- Не подставляй GUID/UUID вручную при `edit_metadata`.
- Для роли используй `setRoleRight` с массивом `rights`.
- Не назначай явные права на `Enum.*`: платформа 1С не поддерживает такие
  права роли на уровне сборки конфигурации.
- Для DCS-запросов и выражений включай доступные проверки
  `validateQueryBeforeWrite`/`validateExpressionBeforeWrite`; если отключаешь
  их из-за ложного срабатывания, фиксируй причину и проверяй другим способом.
- Для `write_module_source` не обходи защиту `confirmFullReplace`. Если правка
  сносит больше половины модуля без явного основания, выбран неверный режим.
- Не считай успешный `dryRun` фактом изменения. Реальная запись подтверждается
  ответом вызова с `dryRun=false` и последующим структурным read/validation.
- Не выставляй `skipSyntaxCheck=true` без явной причины.
- При `replaceLines`/insert перечитывай актуальные строки через
  `code_structure` после любых правок выше по модулю.
- Если `write_module_source` вернул `supportLock`, не обходи его прямой
  файловой правкой: сообщи пользователю и предложи снятие с поддержки или
  работу через расширение.
- Если задача затрагивает запрос/выражение СКД глубоко, подключай skill
  `1c-query`.
- Если задача затрагивает UI формы, оставайся в этом skill и используй
  `edit_metadata` (`addField`, `addButton`, `setProperty`, `moveItem`,
  `removeItem`, `addEventHandler`, `addCommandHandler`,
  `addFormConditionalAppearance`, `setupSettingsComposerOnForm` и др.).
- Если задача - YAxUnit, подключай skill `yaxunit-tests`, но запуск оставляй
  основной сессии.
- Если задача - удаление элемента метаданных, обязательно используй
  `1c-metadata-removal-impact` перед `edit_metadata remove*`.
- Если задача - UI/BDD сценарий, используй `vanessa steps|checkSyntax` перед
  `vanessa run`; не выдумывай Gherkin-шаги без словаря.

## Известные ограничения и осторожности

- `validate_query` без `projectName` проверяет синтаксис и структуру, но не
  подтверждает объекты конфигурации. Для критичных запросов передавай
  `projectName` (при необходимости `projectScope=true`) и дополнительно
  проверяй запись в СКД/код и/или тестовый прогон.
- `code_search useRegex=true` для `textSearch` не поддерживается; используй
  wildcards `*` и `?`. Regex есть в `code_structure find` внутри одного модуля
  и в `dcsSearch`.
- `get_validation_errors scope=session` покажет только файлы, изменённые в
  текущей сессии плагина. Если ничего не правили через MCP/EDT, используй
  `scope=object` или `fileFilter`.
- `scope=project` и `scope=all` на типовых конфигурациях могут вернуть тысячи
  legacy-маркеров; не смешивай их с качеством текущей правки.
- Для внешних обработок/отчётов и расширений сначала читай соответствующие
  help topics: `externalObjectsWorkflow`, `extensionsWorkflow`.
- Состав operations `edit_metadata` развивается. Если старый gap был описан в
  предыдущих версиях skill, не считай его актуальным без проверки help и
  фактического ответа MCP.

## Формат фиксации в research/review

Когда `1c-rsv` повлиял на вывод, фиксируй коротко:

```text
MCP 1c-rsv:
- server: <MCP:RSV Server version, если проверяли>
- project: <name>
- discovery: <list_metadata_objects, code_structure, code_search, ...>
- edits: <edit_metadata operations / write_module_source modes>
- validation: <write_module_source validation или get_validation_errors summary>
- limitations: <MCP unavailable, project scope, supportLock, fallback gap, ...>
```
