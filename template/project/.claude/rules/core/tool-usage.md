# Tool usage policy

Этот файл описывает общий выбор инструментов для чтения, поиска, диагностики,
редактирования и shell-команд.

## Базовый принцип

Используй самый узкий структурированный инструмент, который решает задачу.
Shell не является универсальным fallback для чтения файлов, поиска строк или
диагностики содержимого.

## Матрица выбора инструментов

- Известный файл: `Read`.
- Известный фрагмент или локальный контекст вокруг найденной строки: `Read` с
  узким диапазоном, а не shell-команды для нарезки файла.
- Поиск файлов по маске: `Glob`.
- Поиск текста в файлах: `Grep` или MCP discovery, если зона относится к
  1С/EDT.
- AIDD-артефакты активного тикета: протокол из
  `.claude/rules/core/aidd-artifacts.md`.
- 1С/EDT metadata, BSL, формы, СКД, роли и подсистемы: сначала
  `.claude/skills/1c-rsv-tools/SKILL.md` и доступные MCP tools.
- Редактирование metadata, СКД, форм и ролей: `edit_metadata`, если операция
  покрыта MCP; прямой `Edit`/`Write` только при documented gap/баге MCP и с
  явной фиксацией причины.
- Git status, diff, log и commit helpers: documented git/helper команды по
  `.claude/rules/core/git-workflow.md` и `.claude/skills/aidd-commit-block/SKILL.md`.
- Тесты, validation и внешние CLI: shell допустим, если команда является
  осмысленным CLI-действием, а не способом прочитать или нарезать файл.
- Сложная повторяемая диагностика: project-local helper из `.claude/scripts/*`,
  предпочтительно `.cmd` wrapper на Windows, а не inline `powershell -Command`,
  `python -c`, heredoc или compound shell script.

## Запрещённые shell-паттерны для file inspection

Не используй `Bash`, `PowerShell`, `cmd`, `python -c`, `sed`, `awk`,
`Get-Content`, `Select-String`, `cat`, `head`, `tail`, `ls`, `dir`,
`Get-ChildItem`, `Test-Path`, `rg --files`, shell redirects или pipelines только
для:

- проверки существования известного файла;
- перечисления AIDD-артефактов активного тикета;
- чтения известного файла;
- чтения конкретной строки или диапазона строк;
- нарезки файла перед редактированием;
- byte dump, hex dump, проверки BOM или кодировки известного source-файла;
- обхода проблем с кириллическими путями без явного documented fallback.

Для этих операций используй `Read`, `Glob`, `Grep`, MCP tools или documented
helper из `.claude/scripts`.

## Когда shell допустим

Shell допустим, когда он запускает внешний инструмент или project-local helper,
а не подменяет встроенные file tools:

- `git status`, `git diff`, `git log` и другие read-only git-команды;
- `.claude/scripts/*.cmd`, `.claude/scripts/*.ps1` или `.claude/scripts/*.sh`,
  если конкретный skill/rule предписывает этот helper;
- тесты, linters, EDT/1С validation runners, если они доступны только как CLI;
- `--help` или `--version` для изучения CLI;
- безопасные подготовительные команды, явно описанные в workflow.

На Windows для shell-команд используй repo-relative пути с `/` или quoted
project-local paths. Не используй абсолютные `C:\...` пути в Bash и не ставь
trailing `\` перед пробелом.

## Tooling gaps

Если `Read`, `Glob`, `Grep` или MCP tools формально подходят, но в конкретной
задаче оказываются неэффективны, неудобны или дают неполный контекст, не
обходи это молча через ad-hoc shell.

Зафиксируй `Tooling gap`:

- что пытался сделать;
- какие штатные инструменты использовал;
- почему они неэффективны или недостаточны;
- какой helper, MCP tool, script или permission rule стоит добавить;
- был ли применён временный fallback и почему он безопасен.

Куда фиксировать:

- обычный `implement`: в `tasklist` текущего блока при обновлении блока после
  выполнения;
- `fast-implement`: в PRD отдельным разделом `Implementation notes / Tooling
  gaps`, не меняя требования, статус, решения и acceptance criteria;
- `feedback-fix`: в соответствующей записи `FB-XXX`;
- `review-fix`: в соответствующей записи `RV-XXX`;
- review/research: в `review` или `research` как наблюдение, если gap влияет
  на полноту проверки.

Если tooling gap блокирует безопасное выполнение, остановись и верни blocker
вместо изобретения одноразовой shell-команды.
