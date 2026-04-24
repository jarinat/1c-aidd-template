# Claude Scripts

Этот каталог содержит проверенные entrypoint-скрипты для Claude Code.

Claude не должен заменять эти скрипты inline-командами вида `python -c`,
`python3 -c`, `for ...; do ...`, `find | grep | head` или произвольным shell.

## Разрешенные скрипты

- `commit-block.sh` -- сценарий подготовки commit-блока.
- `aidd-inspect.ps1` -- универсальные read-only проверки внутри корня
  репозитория для AIDD-сценариев.
- `gitlab-mr-review.ps1` -- подготовка GitLab MR review: metadata, fetch refs,
  изолированный worktree под `C:\ai-review-wt`, diff-файлы и cleanup.

## Правила

- Скрипты не принимают произвольный shell-код.
- Read-only скрипты не изменяют файлы.
- Скрипты должны ограничивать работу корнем репозитория и не читать пути через
  `..` за его пределами.
- Project-specific знания не вшиваются в универсальные скрипты. Такие правила
  должны жить в `.claude/rules/project/*` или `.claude/rules/paths/*`.
- GitLab MR review не должен собираться ad-hoc командами `curl`, `python -c`,
  `git credential fill` и ручными `/tmp/*.json`. Используй
  `gitlab-mr-review.ps1` как единственный entrypoint подготовки и cleanup.
