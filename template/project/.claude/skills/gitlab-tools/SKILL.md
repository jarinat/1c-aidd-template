---
name: gitlab-tools
description: >
  Работа с GitLab через glab и project-local script gitlab-tools.cmd: чтение
  замечаний (тредов) merge request, ответы в треды, resolve, статус пайплайна и
  логи упавших job. Используй, когда пользователь просит посмотреть или разобрать
  замечания MR, проверить, исправлены ли они, ответить ревьюеру, узнать статус
  пайплайна или найти причину падения CI.
---

# GitLab tools

Единственный entrypoint для GitLab-операций — `.claude/scripts/gitlab-tools.cmd`.
Он же документирует свои правила расширения в шапке `gitlab-tools.ps1`.

Source of truth:

- политика review: `.claude/rules/core/code-review.md`;
- lifecycle review и статусы: `.claude/rules/core/aidd-workflow.md`,
  `.claude/rules/core/aidd-artifacts.md`;
- выбор инструментов и shell policy: `.claude/rules/core/tool-usage.md`;
- подготовка review-контекста MR (worktree, diff, snapshots):
  `.claude/skills/review-gitlab-mr/SKILL.md`;
- исправление принятого `RV-XXX`: `.claude/skills/aidd-fix-review/SKILL.md`;
- Sonar-находки того же PR: `.claude/skills/aidd-fix-sonar/SKILL.md`.

## Границы

- Не публикуй ничего в GitLab без явного подтверждения пользователя в текущей
  сессии. Сначала покажи полный текст ответа, потом публикуй.
- Заметки уходят от аккаунта пользователя, а не от Claude. Текст ответа — это
  слова пользователя: он должен их увидеть и согласовать до отправки.
- Не ставь и не снимай resolve по своей инициативе: это решение пользователя.
  По спорному треду resolve не ставится вообще, пока ревьюер не ответил.
- Не approve, не merge, не создавай MR и не меняй его описание.
- Не редактируй и не удаляй заметки других пользователей.
- Не заменяй script inline-командами `glab api`, `curl`, `python -c`, shell
  pipelines или временными JSON. Если не хватает операции, добавь подкоманду по
  рецепту из шапки `gitlab-tools.ps1`.
- Не проси и не сохраняй GitLab token: авторизация только через `glab auth`.
- Не дублируй проверки SonarQube: находки Sonar идут через `aidd-fix-sonar`.
- Не меняй текущую ветку пользователя и не делай commit.

## Команды

| Команда | Вид | Назначение |
| --- | --- | --- |
| `threads -MrUrl <url> [-IncludeSystem]` | read | треды MR как JSON, без системного шума |
| `pipeline -MrUrl <url>` | read | последний пайплайн MR и все job, `failed_jobs` — id для логов |
| `pipeline-log -MrUrl <url> -JobId <id> [-Tail <n>]` | read | трейс job, по умолчанию последние 200 строк, `-Tail 0` — весь |
| `reply -MrUrl <url> -DiscussionId <id> -BodyFile <path>` | write | один ответ в существующий тред |
| `resolve -MrUrl <url> -DiscussionId <id> [-Unresolve]` | write | пометить тред решенным или снять пометку |

Read-команды разрешены в `permissions.allow` по префиксу подкоманды.
Write-команды туда не добавляются: каждая публикация должна упираться в
permission-запрос. Wildcard `Bash(.claude/scripts/gitlab-tools.cmd:*)` в allow
добавлять нельзя — он молча выдал бы право писать в GitLab без спроса.

Текст ответа всегда передается файлом через `-BodyFile`, а не строкой в
командной строке: это защищает кириллицу, обратные кавычки и кавычки от
экранирования shell. Файл пиши в scratchpad-каталог сессии.

## Алгоритм: разбор замечаний MR

1. Получи явный `MR_URL` от пользователя. Не угадывай MR по текущей ветке.
2. Определи ticket id из `aidd/docs/.active_ticket` или аргумента.
3. Прочитай треды:

   ```text
   .claude/scripts/gitlab-tools.cmd threads -MrUrl "<MR_URL>"
   ```

4. Для каждого треда проверь фактическое состояние кода **на текущем HEAD**, а
   не по `position` заметки. `position.head_sha` фиксирует ревизию, на которой
   писали замечание: после переименования файла или force-push путь и строка из
   заметки указывают на несуществующее место, а GitLab показывает тред как
   outdated. Сопоставляй по смыслу через `Read`/`Grep` и `git log`, а не по
   пути из заметки.
5. Классифицируй каждое замечание:
   - `FIXED_IN_HEAD` — исправление подтверждено кодом на HEAD и коммитом;
   - `FIX_CANDIDATE` — замечание справедливо, но в коде не отражено;
   - `DISPUTED` — есть техническое основание не исправлять; нужен ответ
     ревьюеру с аргументом, а не молчаливая правка;
   - `UNCLEAR` — замечание неоднозначно, нужен вопрос ревьюеру.
6. Создай или обнови `RV-XXX` в `aidd/docs/review/<ticket>.md` по формату ниже.
   Замечание ревьюера GitLab — внешняя находка, а не пользовательское
   замечание из чата: оно идет в `review`, а не в `feedback`.
   Повторный запуск сопоставляй по note id и не создавай дубликаты. Один MR
   может проходить через несколько подтикетов трекера, поэтому ищи note id по
   всем `review`-файлам тикета.
7. Покажи пользователю классификацию и полные тексты драфтов ответов. Один
   ответ пользователя может согласовать несколько явно перечисленных тредов.
8. Публикуй по одному треду:

   ```text
   .claude/scripts/gitlab-tools.cmd reply -MrUrl "<MR_URL>" -DiscussionId "<id>" -BodyFile "<path>"
   ```

9. `resolve` выполняй только по явному решению пользователя и только для
   тредов, где исправление подтверждено или ревьюер согласился. Тред с открытым
   вопросом к ревьюеру оставляй unresolved.
10. Для принятых `FIX_CANDIDATE` правь код через
    `.claude/skills/aidd-fix-review/SKILL.md`, один `RV-XXX` за запуск.

## Алгоритм: разбор падения пайплайна

1. Получи `MR_URL`, прочитай `pipeline`.
2. Если `failed_jobs` пуст, а пользователь ждет падения, проверь `pipeline.sha`:
   пайплайн может относиться к более старому head.
3. Для каждого упавшего job прочитай `pipeline-log` с небольшим `-Tail`,
   увеличивай только при необходимости. Трейс содержит ANSI-коды и
   `section_start`/`section_end` — это нормальный вывод раннера.
4. Свяжи причину падения с исходником через `Read`/`Grep`. Не делай вывод о
   причине только по имени job.
5. Машинный trace автономных прогонов фиксируется в `aidd/docs/debug/<ticket>.md`
   по `.claude/skills/aidd-debug-loop/SKILL.md`, а не в `review`.

## Формат записи review

```markdown
### RV-XXX — GitLab: <краткая причина>

- Status: OPEN
- Category: <blocking|important|minor>
- Source: GitLab MR
- MR: <iid> (<url>)
- Notes: <note id, ...>
- Reviewer: <username>
- Note position: <path:line @ head_sha> (<actual|outdated>)
- Location: <repo-relative path[:line] на HEAD>
- Evidence: <что подтверждено в коде на HEAD, commit>
- Classification: <FIXED_IN_HEAD|FIX_CANDIDATE|DISPUTED|UNCLEAR>
- Recommendation: <исправление, аргумент ревьюеру или вопрос>
- Decision: <ACCEPTED|DECLINED|пусто>
- Actual fix: <commit или пусто>
- Reply: <note_url опубликованного ответа или пусто>
- Thread: <UNRESOLVED|RESOLVED>
```

Не переписывай исходную evidence и recommendation задним числом. Фактическое
исправление и ответ фиксируй отдельными полями.

## Известные ограничения

- DNS до GitLab-хоста периодически отваливается на первом запросе. Script
  ретраит только DNS-ошибки резолва: они доказывают, что запрос не дошел, и
  повтор не может создать дубль заметки. Любая другая ошибка не ретраится.
- `position` заметки относится к ревизии `head_sha` на момент комментария и
  устаревает при переименованиях и force-push.
- `threads` скрывает системные заметки (`added N commits`, `assigned to`).
  Для полной ленты используй `-IncludeSystem`.
- Создание MR и approve намеренно не реализованы: approve и merge остаются
  ручными действиями в UI.

## Результат

Сообщи: MR и проверенный head, число тредов и их классификацию, созданные или
обновленные `RV-XXX`, что опубликовано (с `note_url`), что осталось
unresolved и почему, следующий шаг.
