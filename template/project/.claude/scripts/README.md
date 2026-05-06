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
- `aidd-bootstrap-ticket.cmd` -- approval-friendly entrypoint для стандартной
  инициализации базовых AIDD-артефактов тикета.
- `aidd-bootstrap-ticket.ps1` -- реализация AIDD bootstrap: `.active_ticket`,
  каталоги `aidd/docs/*` и пустой `feedback`-файл, если он ещё не существует.
  Не вызывай напрямую из Claude Code, используй `.cmd` wrapper.
- `new-guid.cmd` -- approval-friendly entrypoint для генерации новых GUID/UUID
  при ручной правке XML/.mdo и других 1С/EDT артефактов.
- `new-guid.ps1` -- реализация генерации GUID/UUID. Не вызывай напрямую из
  Claude Code, используй `.cmd` wrapper.
- `gitlab-mr-review.cmd` -- approval-friendly entrypoint для GitLab MR review.
- `gitlab-mr-review.ps1` -- реализация GitLab MR review: metadata, fetch refs,
  изолированный worktree под `C:\ai-review-wt`, diff-файлы и cleanup. Не
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
- GitLab MR review не должен собираться ad-hoc командами `curl`, `python -c`,
  `git credential fill` и ручными `/tmp/*.json`. Используй
  `gitlab-mr-review.cmd` как единственный внешний entrypoint подготовки и
  cleanup.
- Для дополнительного чтения MR context из review worktree используй read-only
  subcommands `gitlab-mr-review.cmd`: `show-file`, `grep-file`, `list-files`,
  `grep-tree`. `grep-file` и `grep-tree` поддерживают `-First <count>`, чтобы
  не собирать `Select-Object -First`, `head` или `tail` через shell pipeline.
  Не собирай команды вида `cd "<worktree_path>" && git show ... | grep ...`
  или `powershell -Command "cd ...; git show ... | Select-String ..."`.
- Для GitLab API `gitlab-mr-review.ps1` использует только авторизацию `glab`.
  Токен должен храниться в `glab auth`; fallback на `GITLAB_TOKEN`,
  `GITLAB_ACCESS_TOKEN`, git credential manager, prompt или inline env не
  используется.
- Для постоянного approval не разрешай широкий паттерн `powershell *`; если
  нужно запомнить разрешение, оно должно быть привязано к конкретному `.cmd`
  wrapper в `.claude/scripts/`, например `.claude/scripts/aidd-bootstrap-ticket.cmd`
  `.claude/scripts/new-guid.cmd` или `.claude/scripts/gitlab-mr-review.cmd`.
