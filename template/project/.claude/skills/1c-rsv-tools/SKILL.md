---
name: 1c-rsv-tools
description: >
  Discovery, валидация и редактирование 1С/EDT-конфигурации через MCP-сервер
  1c-rsv (плагин 1С:EDT). Используй как основной слой работы с метаданными,
  СКД, BSL-модулями, формами, ролями, подсистемами, валидацией EDT и
  YAxUnit-запусками. Особенно обязателен при создании и изменении объектов
  метаданных, СКД и BSL, если MCP-сервер доступен.
---

# 1c-rsv-tools

Этот skill описывает правила использования MCP-сервера `1c-rsv`. Сервер
работает поверх запущенного 1С:EDT (HTTP MCP) и даёт read-only discovery,
валидацию EDT и write-операции через штатный API EDT, а не через прямую
правку XML.

## Когда использовать

- Discovery 1С/EDT-кодовой базы: метаданные, BSL-модули, методы, формы,
  ссылки между объектами, иерархия вызовов, callers, локальные reference
  patterns.
- Любое создание или изменение объектов метаданных, реквизитов, табличных
  частей, форм, команд, ролей, подсистем, шаблонов СКД и макетов.
- Любое редактирование BSL-модулей через агентов (`replace`, `append`,
  `insertBefore`, `insertAfter`, `replaceLines`, `replaceMethod`) с
  встроенной EDT-валидацией.
- Валидация EDT-маркеров (`get_validation_errors`) после правок.
- Чтение реальной структуры формы (`get_form_image format=structure`) с
  деревом элементов, кнопок, `commandName`, layout-полей.
- Проверка структуры конфигурации, списка подсистем, статистики объектов.
- Запуск YAxUnit-тестов и отладочных сессий - только из основной сессии,
  не из subagent.

## Когда не использовать

- Для маленького точечного чтения известного файла, где достаточно `Read`.
- Для прямой правки `*.mdo`, `*.form`, `*.dcs` через `Write`/`Edit`. Это
  обходит EDT-API и может сломать целостность ссылок и GUID.
- Для генерации новых GUID/UUID. См. `.claude/rules/core/onec-general.md`:
  GUID создаются через `.claude/scripts/new-guid.cmd`, а `1c-rsv` сам
  управляет GUID при создании объектов через `edit_metadata`.

## Доступные инструменты

### Workspace и EDT info (read-only)

- `list_workspace_projects` - открытые 1С-проекты EDT.
- `list_applications` - Run Configurations (ИБ) проекта.
- `show_edt_version` - версия EDT.
- `get_config_properties` - свойства конфигурации, статистика, подсистемы.

### Discovery: метаданные (read-only)

- `list_metadata_objects` - каталог объектов по типу/маске, с пагинацией.
- `get_object_details` - структура одного объекта: реквизиты, табличные
  части, формы, измерения, ресурсы, DCS templates, subsystem links.
- `get_object_help` - синоним, путь к `mdo`, html-help.
- `code_search operation=objectReferences` - BSL-ссылки на объект (`deep`
  ищет производные типы вроде `СправочникСсылка.X`, `simple` - точное имя).
- `code_search operation=textSearch` - текстовый поиск по BSL и связанным
  артефактам, включая схемы СКД и запросы динамических списков.
- `code_search operation=help topic=workflow` - краткий путеводитель по
  сценариям поиска.

### Discovery: модули и методы (read-only)

- `list_modules` - каталог BSL-модулей с фильтрами по типу/объекту/имени.
- `get_module_structure` - список процедур/функций модуля с
  doc-комментариями.
- `read_module_source` - чтение модуля целиком или диапазона строк.
- `read_method_source` - чтение одного метода.
- `code_search operation=resolveSymbol` - go to definition по
  `Модуль.Метод`.
- `code_search operation=methodReferences` - ссылки на конкретный метод.
- `code_search operation=callHierarchy` - иерархия вызовов (depth 1-3).

### Discovery: формы и сводка (read-only)

- `get_form_image` - структура формы: дерево элементов, кнопки,
  `commandName`, position, представления; или PNG. Параметры пагинации:
  `depth`, `subtree`, `maxElements`.
- `ai_context` - сборщик контекста по объекту/форме/модулю/методу
  (depth `minimal`/`standard`/`full`). Полезен на старте discovery вместо
  серии отдельных вызовов.

### Платформенная справка (read-only)

- `get_platform_docs` - справочник платформы 1С: API, BSL, язык запросов,
  СКД-функции, аннотации расширений, директивы компиляции.

### Валидация (read-only)

- `validate_query` - Xtext-валидатор языка запросов. В MCP 4.2.0 подтверждён
  дефект: standalone-валидатор может выдавать ложные синтаксические ошибки
  даже на простых запросах с русскими ключевыми словами (`ВЫБРАТЬ`,
  `КАК`, `ИЗ`). Не используй standalone `validate_query` как источник истины
  для обычных запросов 1С.
- `get_validation_errors` - EDT-маркеры. Дефолт `scope=session` (только файлы,
  изменённые в текущей сессии плагина). `scope=object` - все файлы одного
  объекта. `scope=project` - только осознанно с `confirmLargeResult=true`,
  иначе срабатывает предохранитель.
- `diff_module` - сравнение BSL-модуля с git-версией: `summary`, `unified`,
  `methods`.

### Edit (write через EDT-API)

- `edit_metadata` - единый конструктор операций: `createObject`,
  `setObjectProperty`, `addObjectAttribute`, `addTabularSection`,
  `addFormAttribute`, `addField`, `addGroup`, `addButton`, `addTable`,
  `addDecoration`, `addCommandHandler`, `addEventHandler`,
  `createReportSchema`, `addDataSet`, `addDataSetField`,
  `addCalculatedField`, `addTotalField`, `addSchemaParameter`,
  `addSettingsGroup`, `addSettingsTable`, `addSettingsSelectedField`,
  `addSettingsFilter`, `addSettingsOrder`, `addConditionalAppearance`,
  `setRoleRight`, `addRegisterField`, `removeRegisterField`,
  `addSubsystemContent`, `adoptObject`, `adoptObjects`, `adoptChild`,
  `adoptModule`, `addTemplate`, `drawTemplate`, `setTemplateCell`,
  `mergeTemplateCells`, `setDefinedTypeTypes` и др.
  Для справки используй `edit_metadata operation=help` и
  `topic=workflow|dcsWorkflow|registersWorkflow|matrixWorkflow|composerWorkflow|dryRun|<имя_операции>`.
  Поддерживается `dryRun=true`.
- `write_module_source` - запись BSL: `replace`, `append`, `insertBefore`,
  `insertAfter`, `replaceLines`, `replaceMethod`. Дефолт `dryRun=true`,
  встроенная EDT-валидация возвращается в поле `validation`. Для массовой
  замены модуля требуется `confirmFullReplace=true`.
- `export_object` - экспорт внешней обработки/отчёта в `.epf`/`.erf`.

### Build, БД, тесты, отладка

Эти tools действуют на ИБ или процесс EDT. Используй только из основной
сессии и только при явном пользовательском решении.

- `rebuild_project` - clean build EDT-проекта.
- `sync_database` - обновление ИБ из конфигурации.
- `yaxunit_tests` - запуск YAxUnit с фильтрами и Markdown-отчётом.
- `launch_debugger` - управление debug-сессией.

## Базовый workflow

1. Перед discovery зафиксируй `projectName` через
   `list_workspace_projects` или из явного указания пользователя/AIDD-
   артефактов. Дальше всегда передавай `projectName` явно - не полагайся
   на первый найденный проект.
2. Для discovery предпочитай:
   - `list_metadata_objects nameMask` для поиска объектов по имени;
   - `get_object_details` для структуры;
   - `code_search operation=objectReferences` для зависимостей;
   - `code_search operation=methodReferences|callHierarchy|resolveSymbol`
     для методов и переходов к определению;
   - `ai_context depth=standard` для сводки по объекту/форме/модулю.
3. Для редактирования метаданных и СКД всегда используй `edit_metadata`,
   а не прямую правку `*.mdo`, `*.form`, `*.dcs`. Сначала изучи нужную
   операцию через `edit_metadata operation=help topic=...`.
4. Для редактирования BSL используй `write_module_source` с `dryRun=true`
   на спорных правках, читай `validation` из ответа реальной записи.
5. После change-блока проверь маркеры:
   - `get_validation_errors scope=session` - что сделано в этой сессии;
   - `scope=object objectName=<FQN>` - фокус на изменённом объекте.
6. Не вызывай `sync_database`, `rebuild_project`, `yaxunit_tests` или
   `launch_debugger` из subagent. Эти операции принимает только основная
   сессия по решению пользователя.
7. Не используй `validate_query` как единственный валидатор. Для запросов СКД
   предпочитай встроенную проверку `edit_metadata`, валидацию EDT или
   фактический прогон в окружении. Если `validateQueryBeforeWrite=true` даёт
   поток синтаксических ошибок на русских ключевых словах, отключи его
   локально с фиксацией причины и проверь запрос другим способом.

## Правила безопасности и качества

- Никогда не редактируй `*.mdo`, `*.form`, `*.dcs` через `Write`/`Edit`,
  если есть соответствующая операция `edit_metadata`. Исключение допустимо
  только при gap/баге MCP, после фиксации причины и с явным решением
  пользователя.
- При создании объектов метаданных не подставляй GUID/UUID вручную:
  `edit_metadata` сам управляет идентификаторами.
- Для роли используй `setRoleRight` с массивом `rights`, а не поштучно.
- Не назначай явные права на `Enum.*`: платформа 1С не поддерживает такие
  права в роли на уровне сборки конфигурации. MCP `setRoleRight` в `dryRun`
  может принять такую операцию, но это не доказывает корректность результата.
  Доступ к значениям перечислений обеспечивается через права на объекты-
  владельцы реквизитов (`Document`, `Catalog` и т. п.).
- Для DCS-выражений включай `validateExpressionBeforeWrite`, если операция
  поддерживает такую проверку. На специфичных функциях возможны ложные
  срабатывания - отключай локально с пояснением.
- Для `write_module_source` всегда указывай явный `mode`:
  - `replaceMethod` для одной процедуры/функции по имени;
  - `replaceLines` с диапазоном для локальных правок;
  - `insertBefore`/`insertAfter` для точечных вставок внутри метода;
  - `replace` только при необходимости полной замены модуля и с
    `confirmFullReplace=true`.
- Для вендорских или типовых модулей с doc-comment над методом используй
  `replaceMethod` только если replacement source включает doc-comment. В MCP
  4.2.0 `read_method_source` возвращает метод вместе с doc-comment, и такой
  сценарий сохраняет комментарий. Если передать только код от строки
  `Процедура`/`Функция`, комментарий перед методом будет удалён. Для точечной
  правки внутри тела метода предпочитай `insertBefore`/`insertAfter` или
  `replaceLines`.
- Не обходи защиту `confirmFullReplace`. Если правка сносит больше половины
  модуля без явного основания, это сигнал, что выбран не тот режим.
- Не выставляй `skipSyntaxCheck=true` без явной причины.
- Не вызывай `sync_database`, `rebuild_project`, `yaxunit_tests`,
  `launch_debugger` из subagent. Это write-операции окружения, не исходников.
- Если запрос/выражение СКД требует проверки и оптимизации, переходи на skill
  `1c-query`.
- Если задача затрагивает форму как UI (`Form.form` элементы и обработчики),
  оставайся в этом skill; редактирование делай через `edit_metadata`
  (`addField`, `addButton`, `setProperty`, `moveItem`, `removeItem`,
  `addCommandHandler`, `addEventHandler`). Если нужная операция не покрыта MCP,
  зафиксируй `Tooling gap` и получи явное решение пользователя перед прямой
  правкой `Form.form`.
- Если задача - YAxUnit, переходи на skill `yaxunit-tests`. Запуск тестов
  оставляй основной сессии.
- Если задача - удаление элемента метаданных, обязательно используй
  `1c-metadata-removal-impact` перед `edit_metadata` `remove*`.

## Известные ограничения 1c-rsv

- `validate_query` в MCP 4.2.0 непригоден как самостоятельный валидатор
  обычных запросов 1С: подтверждены ложные ошибки даже на `ВЫБРАТЬ 1 КАК
  Field`. Если валидатор даёт поток синтаксических ошибок на русских ключевых
  словах, идентификаторах или строках, не трактуй это как факт ошибки запроса
  без альтернативной проверки.
- Для модулей объектов метаданных параметр `modulePath` не всегда корректно
  резолвится через произвольную кириллическую папку. Надёжнее использовать
  `objectName + moduleType`.
- В `scope=project` `get_validation_errors` срабатывает предохранитель при
  большом числе ошибок. Не обходи его через `confirmLargeResult` без явной
  необходимости.
- `edit_metadata` может не покрывать отдельные свойства метаданных и СКД:
  например `datePart=Date` у измерения, `useRestriction` у параметра СКД,
  права на `Configuration.*`, свойства роли `setForAttributesByDefault`,
  `setForNewObjects`, `independentRightsOfChildObjects`, замену или удаление
  существующего `calculatedField`. В таких случаях сначала проверь help
  операции, затем оформи точечный fallback с причиной и проверкой diff.
- `addCalculatedField` может добавить дубль вместо замены существующего поля.
  Перед применением проверь наличие поля и не считай операцию replace-ом, если
  help явно этого не обещает.
- Для регистров в MCP 4.2.0 актуальный workflow: `createObject` с массивами
  `dimensions`/`resources`/`recorders` или последующий `addRegisterField`.
  Не используй устаревшее имя операции `addDimension`, если `help` его не
  подтверждает.

## Формат фиксации в research/review

Когда `1c-rsv` повлиял на вывод, фиксируй коротко:

```text
MCP 1c-rsv:
- project: <name>
- discovery helpers: <list_metadata_objects, get_object_details, ...>
- edits: <edit_metadata operations / write_module_source modes>
- validation: <session/object summary, errors/warnings counts>
- limitations: <validate_query кириллица, modulePath кириллица, ...>
```
