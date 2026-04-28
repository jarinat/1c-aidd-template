---
name: review-gitlab-mr
description: >
  Review GitLab merge request по ссылке. Используй для сценария
  review-gitlab-mr: получить MR metadata из GitLab, подготовить изолированный
  git worktree, проверить diff через review-mr и вывести отчёт в текущую
  сессию без публикации комментариев в GitLab.
---

# Review GitLab Merge Request

Используй subagent `review-mr` как review engine.

Source of truth:

- MR review engine:
  - `.claude/skills/review-mr/SKILL.md`
- общая политика code review:
  - `.claude/rules/core/code-review.md`
- специализированные проверки:
  - `1c-query`
  - `edt-form-editing`
  - `yaxunit-tests`

## Назначение

Этот skill связывает review с конкретным GitLab merge request, а не только с
парой веток. Пользователь передаёт ссылку на MR, а результат review выводится в
текущую сессию Claude Code.

По умолчанию skill работает в read-only режиме относительно MR:

- не исправляет код;
- не публикует комментарии в GitLab;
- не approve/revoke/merge MR;
- не переключает текущую рабочую ветку пользователя.
- не использует `rlm-tools-bsl`/MCP discovery, потому что MR проверяется в
  отдельном worktree, а индекс RLM может относиться к другой рабочей копии.

## Вход

- `MR_URL` — ссылка на GitLab merge request вида
  `https://gitlab.example.com/group/project/-/merge_requests/123`.

Опционально:

- `PUBLISH=false|true` — по умолчанию `false`. Режим `true` не выполняй без
  отдельного явного подтверждения пользователя в текущей сессии.

## Требования к инструментам

Обязательный путь подготовки:

- используй только project-local script
  `.claude/scripts/gitlab-mr-review.cmd prepare`;
- `.cmd` является approval-friendly wrapper над
  `.claude/scripts/gitlab-mr-review.ps1`; не вызывай `.ps1` напрямую, чтобы
  Claude Code не предлагал постоянное разрешение вида `powershell *`;
- не собирай подготовку MR ad-hoc командами `curl`, `python -c`,
  `git credential fill`, shell pipelines или временными `/tmp/*.json`;
- после `prepare` не используй shell-команды для чтения MR context. Не вызывай
  `.cmd show-file`, `.cmd grep-file`, `.cmd list-files`, `.cmd grep-tree`,
  `.ps1`, `cmd /c`, `powershell`, `git show`, `Select-Object`, `head`, `tail`,
  `grep` или pipelines. Контекст для review должен быть материализован в
  manifest directory и читаться через `Read`, `Glob`, `Grep`;
- не реконструируй и не декодируй repo-relative paths вручную из escaped Git
  output. Пути бери дословно из `diff_name_status_path`, `diff_patch_path` и
  `changed_files_path`;
- если script отсутствует или завершился ошибкой, остановись и объясни причину
  из вывода script.

Script сам получает metadata через GitLab API только через `glab auth` для
GitLab host из `MR_URL`. Не используй и не предлагай fallback на
`GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN`, git credential manager, prompt или
inline env. Не проси пользователя присылать token в чат.

## Алгоритм

1. Проверь, что пользователь передал `MR_URL`.
2. Подготовь review context одной командой из корня целевого репозитория:

   ```powershell
   .claude/scripts/gitlab-mr-review.cmd prepare -MrUrl "<MR_URL>"
   ```

3. Используй JSON manifest из stdout и `manifest_path` как source of truth для:
   - `mr_url`, `title`, `description`;
   - `source_branch`, `target_branch`;
   - `base_sha`, `head_sha`;
   - `worktree_path`;
   - `diff_stat_path`, `diff_name_status_path`, `diff_patch_path`;
   - `changed_files_path`, `base_snapshot_root`, `head_snapshot_root`.
4. Зафиксируй в контексте review конкретный `head_sha`. Если script сообщает,
   что `diff_refs` ещё пустой или MR не подготовлен GitLab, остановись и
   попроси повторить позже.
5. Не используй текущую рабочую копию пользователя для чтения окружающего кода.
   После `prepare` не запускай shell-команды для чтения MR context. Для `HEAD`
   читай файлы из `worktree_path` или `head_snapshot_root`; для `BASE` читай
   только файлы из `base_snapshot_root`. Используй `changed_files_path` как
   карту materialized snapshots.
6. Передай subagent `review-mr`:
   - `MR_URL`, title, source/target branches;
   - `REVIEW_WORKTREE=<worktree_path>`;
   - `BASE_REF=<base_sha>`;
   - `HEAD_REF=<head_sha>`;
   - содержимое `diff_stat_path` и `diff_name_status_path`;
   - manifest paths в backticks, чтобы Windows `\_` не терялся при отображении:
     `diff_stat_path`, `diff_name_status_path`, `diff_patch_path`,
     `changed_files_path`, `mr_json_path`, `base_snapshot_root`,
     `head_snapshot_root`;
   - требование брать repo-relative paths дословно из manifest-файлов или
     `changed_files_path`, без ручной реконструкции кириллических имён;
   - требование не использовать `Bash`, `cmd`, `powershell`, `.cmd`, `.ps1`,
     `git` или shell pipelines внутри subagent review;
   - требование читать MR context через `Read`, `Glob`, `Grep` по
     `REVIEW_WORKTREE`, `base_snapshot_root` и `head_snapshot_root`.
7. Сформируй итоговый отчёт review:
    - MR title/link;
    - проверенные `base_sha` и `head_sha`;
    - краткая статистика diff;
    - `blocking`, `important`, `minor`;
    - явная фиксация, что замечаний нет, если review чистый;
    - статус cleanup: `worktree removed: <path>` или `worktree kept: <path>`
      с причиной.
8. До вывода итогового отчёта удали review worktree по умолчанию:
    - если пользователь заранее явно попросил оставить worktree, не удаляй его;
    - если review не удалось завершить из-за ошибки инструментов или нужно
      сохранить каталог для ручной диагностики, не удаляй его и явно объясни
      причину в отчёте;
    - в обычном успешном сценарии выполни cleanup только через script:

      ```powershell
      .claude/scripts/gitlab-mr-review.cmd cleanup -WorktreePath "<worktree_path>"
      ```

    - не удаляй worktree вручную через `rm`, `Remove-Item` или shell-цепочки.
9. Выведи итоговый отчёт review в текущую сессию уже с фактическим cleanup
    статусом.

## Публикация в GitLab

По умолчанию не публикуй review в MR.

Если пользователь отдельно попросил опубликовать результат:

1. Сначала покажи текст комментария и спроси явное подтверждение.
2. Публикуй только один общий комментарий к MR, не inline thread.
3. Используй `glab mr note <iid> -m "<message>" -R <repo>` или GitLab Notes
   API `POST /projects/:id/merge_requests/:merge_request_iid/notes`.
4. Не используй GitLab Discussions API для line-comments, пока это не станет
   отдельным явно согласованным сценарием.
5. После публикации сообщи URL MR и, если доступно, ID созданной note.

## Ограничения

- Не меняй текущую ветку пользователя.
- Не заменяй `.claude/scripts/gitlab-mr-review.cmd prepare` inline-командами,
  самописными `curl`/`python`/`git credential` последовательностями или
  временными файлами вне manifest, созданного script.
- Не вызывай `.claude/scripts/gitlab-mr-review.ps1` напрямую из skill: внешний
  entrypoint для Claude Code должен оставаться `.cmd`.
- Не используй `.cmd show-file`, `.cmd grep-file`, `.cmd list-files`,
  `.cmd grep-tree`, `cd "<worktree_path>" && git ...`,
  `git -C "<worktree_path>" ...` или shell pipelines для чтения файлов из
  `base_sha`/`head_sha`. Не используй `powershell -Command`, `cmd /c`,
  `Select-String`, `Select-Object`, `head`, `tail` или `grep` как fallback для
  чтения MR-context; если контекста нет в snapshots, остановись и сообщи, что
  нужно материализовать в `prepare`.
- Не используй `rlm-tools-bsl` и связанные MCP-инструменты для discovery или
  выводов по MR. Для review опирайся на manifest-файлы, materialized snapshots,
  `Read`, `Glob`, `Grep` и локальное чтение файлов внутри `REVIEW_WORKTREE`.
- Не делай `git checkout`, `git switch`, `git pull`, `git merge` или `git
  rebase` в основной рабочей копии.
- Не оставляй review worktree автоматически после успешного review. Оставлять
  его можно только по явной просьбе пользователя или при диагностической
  необходимости; в отчёте обязательно укажи причину.
- Не запрашивай и не сохраняй GitLab token в файлах проекта.
- Не исправляй код автоматически в рамках review GitLab MR.
- Не дублируй проверки Сонара.
- Не придумывай замечания, если проблем нет.
