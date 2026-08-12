# Claude Scripts

Этот каталог содержит проверенные entrypoint-скрипты для Claude Code.

Claude не должен заменять эти скрипты inline-командами вида `python -c`,
`python3 -c`, `for ...; do ...`, `find | grep | head` или произвольным shell.

Deterministic блокировки shell-паттернов живут отдельно в `.claude/hooks` и
подключаются через `.claude/settings.json`.

## Разрешенные скрипты

- `commit-block.sh` -- сценарий подготовки commit-блока.
- `aidd-inspect.ps1` -- универсальные read-only проверки внутри корня
  репозитория для AIDD-сценариев.
- `aidd-inspect.cmd` -- approval-friendly entrypoint для `aidd-inspect.ps1`.
  Не вызывай `.ps1` напрямую из Claude Code, используй `.cmd` wrapper.
- `aidd-bootstrap-ticket.cmd` -- approval-friendly entrypoint для стандартной
  инициализации базовых AIDD-артефактов тикета.
- `aidd-bootstrap-ticket.ps1` -- реализация AIDD bootstrap: `.active_ticket`,
  каталоги `aidd/docs/*` и пустой `feedback`-файл, если он ещё не существует.
  Не вызывай напрямую из Claude Code, используй `.cmd` wrapper.
- `new-guid.cmd` -- approval-friendly entrypoint для генерации новых GUID/UUID
  при ручной правке XML/.mdo и других 1С/EDT артефактов.
- `new-guid.ps1` -- реализация генерации GUID/UUID. Не вызывай напрямую из
  Claude Code, используй `.cmd` wrapper.
- `gitlab-tools.cmd` -- approval-friendly entrypoint для GitLab-операций через
  `glab`: треды MR (`threads`), пайплайны (`pipeline`, `pipeline-log`), общие
  комментарии, ответы, inline review-треды и resolve (`note`, `reply`,
  `discuss`, `resolve`). Сценарий и границы —
  `.claude/skills/gitlab-tools/SKILL.md`.
- `gitlab-tools.ps1` -- реализация GitLab-операций: явные валидируемые
  подкоманды, ретрай только на DNS-ошибках, тело заметки только из файла. Не
  вызывай напрямую из Claude Code, используй `.cmd` wrapper. Правила
  расширения описаны в шапке самого скрипта.
- `http-smoke.cmd` -- approval-friendly entrypoint для HTTP-smoke runner-а,
  разрешённого только когда `aidd-debug-loop` или test/debug plan явно
  указывает этот runner.
- `http-smoke.ps1` -- реализация HTTP-smoke runner-а: одиночный HTTP-вызов,
  profile/config resolution, body из файла или inline, expected
  status/substring, structured JSON output, exit codes (0=PASS, 1=FAIL,
  3=NETWORK, 4=ENV, 5=USAGE). Поддерживает `{{TIMESTAMP}}` в body. Не
  вызывай напрямую из Claude Code, используй `.cmd` wrapper.

## Правила

- Скрипты не принимают произвольный shell-код.
- Read-only скрипты не изменяют файлы.
- AIDD bootstrap не собирай inline-командами `touch`, `mkdir`, `test -f`,
  `New-Item`, `powershell -File` или shell-комбинациями; используй
  `aidd-bootstrap-ticket.cmd`.
- GUID/UUID для ручной правки 1С/EDT артефактов не генерируй inline-командами
  `powershell`, `python`, `uuidgen` или похожими ad-hoc вызовами; используй
  `new-guid.cmd`.
- Скрипты должны ограничивать работу корнем репозитория и не читать пути через
  `..` за его пределами.
- Project-specific знания не вшиваются в универсальные скрипты. Такие правила
  должны жить в `.claude/rules/project/*` или `.claude/rules/paths/*`.
- Настройки HTTP-smoke живут в `.claude/config/http-smoke.local.json`
  (machine-local, не коммитится) или в явно переданном `-ConfigFile`.
  Версионируемый `.claude/config/http-smoke.example.json` содержит только
  пример профилей без секретов.
- Подготовка и cleanup review merge request в этом каталоге не живут: их
  выполняет корпоративный `tools/ai/mpl-review-mr` (на Windows launcher
  `.cmd`) в рамках skill `mpl-review-mr`, а получение Sonar-отчёта --
  корпоративный `tools/ai/mpl-sonar-issues` в рамках `mpl-sonar-evidence`.
  Не собирай их ad-hoc командами `curl`, `python -c`, `git credential fill`
  и ручными `/tmp/*.json`.
- Для review diff используй read-only subcommands
  `.claude/scripts/aidd-inspect.cmd review-diff summary|bsl|metadata|file`.
  Не делай выводы по усеченному diff через `head`, `Select-Object -First` или
  похожие ограничения.
- Для постоянного approval не разрешай широкий паттерн `powershell *` или
  `.claude/scripts/*`. Если нужно запомнить разрешение, оно должно быть
  привязано к конкретному `.cmd` wrapper в `.claude/scripts/`, например
  `.claude/scripts/aidd-bootstrap-ticket.cmd`,
  `.claude/scripts/aidd-inspect.cmd`, `.claude/scripts/new-guid.cmd` или
  `.claude/scripts/http-smoke.cmd`.
- Если скрипт совмещает read- и write-операции, разрешение выдается по
  префиксу подкоманды, а не на скрипт целиком. Для `gitlab-tools.cmd` в
  `permissions.allow` входят только `threads`, `pipeline`, `pipeline-log` и
  `help`; `reply` и `resolve` намеренно остаются без разрешения, чтобы каждая
  публикация в GitLab упиралась в permission-запрос. Wildcard
  `Bash(.claude/scripts/gitlab-tools.cmd:*)` добавлять в allow нельзя.
- HTTP-smoke runner используется только в рамках `aidd-debug-loop`, когда
  test plan в `aidd/docs/debug/<ticket>.md` его явно указывает. URL стендов
  и профили — через `.claude/config/http-smoke.local.json`; креды и токены —
  только через env vars, на которые ссылается config (`usernameEnv`,
  `passwordEnv`) или через одноразовый `-Header` в текущей сессии.
- При добавлении нового переносимого `.cmd` entrypoint в этот каталог проверь,
  нужно ли добавить для него точечное разрешение в `.claude/settings.json`.
  Не добавляй разрешение автоматически для `.ps1` реализации.
