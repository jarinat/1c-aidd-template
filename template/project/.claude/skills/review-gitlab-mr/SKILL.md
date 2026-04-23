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

Предпочтительный путь:

- `glab` установлен и авторизован для GitLab host из `MR_URL`.

Fallback:

- GitLab API через `curl` или аналогичный read-only HTTP client;
- токен берётся только из уже настроенной среды (`GITLAB_TOKEN`,
  `GITLAB_ACCESS_TOKEN`, credential manager, конфиг `glab`). Не проси
  пользователя присылать token в чат.

Если `glab` и API недоступны, остановись и объясни, что нужно настроить.

## Алгоритм

1. Проверь, что пользователь передал `MR_URL`.
2. Распарси из `MR_URL`:
   - GitLab host;
   - project path;
   - MR IID.
3. Проверь, что текущий репозиторий относится к target project из `MR_URL`.
   Если это другой репозиторий, остановись: review должен запускаться из
   checkout-а целевого проекта или его worktree.
4. Получи metadata MR:
   - title;
   - description, если доступно и она нужна для понимания scope;
   - `source_branch`;
   - `target_branch`;
   - `source_project_id`;
   - `target_project_id` или `project_id`;
   - `diff_refs.base_sha`;
   - `diff_refs.head_sha`;
   - `web_url`.
   Предпочтительный способ через `glab`: после парсинга URL используй MR IID и
   repo selector, например `glab mr view <iid> -R <project-url> -F json`.
   Не полагайся на то, что все версии `glab mr view` принимают полный MR URL
   как positional argument.
5. Зафиксируй в контексте review конкретный `head_sha`. Если `diff_refs` ещё
   пустой или MR не подготовлен GitLab, остановись и попроси повторить позже.
6. Не используй текущую рабочую копию пользователя для чтения окружающего кода.
   Подготовь отдельный worktree:
   - всегда размещай review worktree под единым коротким корнем
     `C:\ai-review-wt`;
   - путь формируй как
     `C:\ai-review-wt\<repo-name>-review-mr-<iid>-<short-sha>`;
   - не размещай review worktree внутри текущего репозитория, `.claude/` или
     рядом с проектом: поведение не должно зависеть от `.gitignore` проекта;
   - перед созданием проверь `git worktree list`;
   - если worktree для того же MR и `head_sha` уже существует, переиспользуй
     его;
   - если каталог существует, но указывает на другой `head_sha`, создай новый
     каталог с уникальным суффиксом.
7. Получи refs без переключения текущей ветки:
   - `git fetch origin $TARGET_BRANCH`;
   - `git fetch origin refs/merge-requests/<iid>/head:refs/remotes/origin/mr/<iid>/head`
     если GitLab MR head ref доступен;
   - если head ref недоступен, fetch source branch из metadata MR. Для MR из
     fork сначала проверь, что remote/source project доступен; если нет,
     остановись с понятным сообщением.
8. Создай worktree в detached/head-safe режиме от проверяемого commit:
   - используй `git -c core.longpaths=true worktree add --detach
     <worktree-path> <head_sha>` или эквивалент от `origin/mr/<iid>/head`;
   - предпочтительно от `diff_refs.head_sha` или `origin/mr/<iid>/head`;
   - не checkout-и source branch в основной рабочей копии.
   - если создание worktree завершилось ошибкой, сразу выполни cleanup
     частичного каталога и `git worktree prune`, затем остановись или повтори
     только после понятного исправления причины.
9. Внутри worktree вычисли diff:
   - `git diff <base_sha>...<head_sha> --stat`;
   - `git diff <base_sha>...<head_sha> --name-status --find-renames`;
   - `git diff <base_sha>...<head_sha> --find-renames`.
10. Запусти subagent `review-mr`, передав:
   - `MR_URL`, title, source/target branches;
   - `REVIEW_WORKTREE` — абсолютный путь к worktree;
   - `BASE_REF=<base_sha>`;
   - `HEAD_REF=<head_sha>`;
   - diff stat и name-status;
   - требование выполнять чтение файлов и `git diff` только внутри
     `REVIEW_WORKTREE`.
11. Сформируй итоговый отчёт review:
    - MR title/link;
    - проверенные `base_sha` и `head_sha`;
    - краткая статистика diff;
    - `blocking`, `important`, `minor`;
    - явная фиксация, что замечаний нет, если review чистый;
    - статус cleanup: `worktree removed: <path>` или `worktree kept: <path>`
      с причиной.
12. До вывода итогового отчёта удали review worktree по умолчанию:
    - если пользователь заранее явно попросил оставить worktree, не удаляй его;
    - если review не удалось завершить из-за ошибки инструментов или нужно
      сохранить каталог для ручной диагностики, не удаляй его и явно объясни
      причину в отчёте;
    - в обычном успешном сценарии выполни
      `git worktree remove --force <worktree-path>` и затем `git worktree prune`;
    - не удаляй произвольные каталоги: cleanup разрешён только для пути,
      построенного под `C:\ai-review-wt`.
13. Выведи итоговый отчёт review в текущую сессию уже с фактическим cleanup
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
- Не используй `rlm-tools-bsl` и связанные MCP-инструменты для discovery или
  выводов по MR. Для первого варианта review опирайся на `git diff`, `Read`,
  `Glob`, `Grep` и локальное чтение файлов внутри `REVIEW_WORKTREE`.
- Не делай `git checkout`, `git switch`, `git pull`, `git merge` или `git
  rebase` в основной рабочей копии.
- Не оставляй review worktree автоматически после успешного review. Оставлять
  его можно только по явной просьбе пользователя или при диагностической
  необходимости; в отчёте обязательно укажи причину.
- Не запрашивай и не сохраняй GitLab token в файлах проекта.
- Не исправляй код автоматически в рамках review GitLab MR.
- Не дублируй проверки Сонара.
- Не придумывай замечания, если проблем нет.
