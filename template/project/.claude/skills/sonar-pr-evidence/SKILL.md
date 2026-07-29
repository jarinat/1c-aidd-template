---
name: sonar-pr-evidence
description: >
  Получение и проверка read-only SonarQube issues для одного Pull Request.
  Используй как общий contract для MR review и AIDD-разбора Sonar, когда
  нужен проверяемый JSON-отчёт без изменения SonarQube или исходного кода.
disable-model-invocation: true
---

# Sonar PR evidence

Это общий read-only contract. Единственный entrypoint получения данных —
`tools/scripts/download-sonar-issues.os`, вызываемый через approval-friendly
wrapper `.claude/scripts/download-sonar-issues.cmd` на Windows. Wrapper не
добавляет API или аутентификацию; не заменяй helper `curl`, inline API, другим
клиентом или способом аутентификации.

## Границы

- Один запуск относится к одному явно переданному `PR_IID`.
- Не выводи `SONAR_TOKEN`, не передавай его в аргументах и не сохраняй в JSON.
- Не меняй Sonar issues, status, assignee, comments, configuration или quality
  profile.
- Не считай issue автоматически верным: этот contract поставляет evidence, а
  инженерная проверка кода и правил выполняется вызывающим workflow.
- Для GitLab MR review report сохраняй вне рабочего репозитория, в каталоге
  manifest; generated Sonar report не добавляй в Git.

## Вход

- `PR_IID` — номер Pull Request из GitLab manifest.
- `HEAD_SHA` — обязательный для GitLab MR review SHA из manifest.
- `OUTPUT_DIR` — каталог результата. Для GitLab MR review это дочерний каталог
  directory, содержащего `manifest_path`; для standalone AIDD допустим штатный
  `out/sonar-reports`.

## Алгоритм

1. Проверь наличие `tools/scripts/download-sonar-issues.os`, `oscript`,
   `sonar-project.properties` и непустой `SONAR_TOKEN`, не печатая значение
   token.
2. Запусти только:

   ```text
   .claude/scripts/download-sonar-issues.cmd -pr <PR_IID> -output-dir "<OUTPUT_DIR>"
   ```

3. Прочитай точный path `issues-pr-<PR_IID>.json` из `OUTPUT_DIR`. Проверь:
   - корректный JSON object и `schema: sonar-pr-issues.v2`;
   - `pullRequest` в корне точно равен запрошенному IID;
   - `total` — неотрицательное число и равен `issues.length`;
   - каждый issue содержит `key`, `rule`, `message`, `component` и
     однозначный line/textRange location;
   - если issue содержит `pullRequest`, он также равен запрошенному IID.
4. Для GitLab MR review проверь `analysis`:
   - `analysis.status` равен `available`;
   - `analysis.revision` — полный SHA и побайтно совпадает с `HEAD_SHA` без
     нормализации или предположений;
   - `analysis.taskId`, `analysis.revisionProperty` и, если Sonar его отдал,
     `analysisId`/`executedAt` сохраняются как evidence.
5. Верни вызывающему workflow prepared path, coverage и причину:

   | Coverage | Когда ставить |
   | --- | --- |
   | `verified` | JSON полон, PR совпадает, и Sonar revision точно равен `HEAD_SHA`. |
   | `unavailable` | Полный issues report не получен: нет `oscript`, конфигурации, token, доступа к Sonar или helper завершился ошибкой. |
   | `incomplete` | JSON/пагинация/обязательные поля невалидны или список issues усечён. |
   | `stale` | Sonar отдал revision, но она не равна `HEAD_SHA`. |
   | `unverified` | Issues report полон и относится к запрошенному PR, но revision evidence отсутствует, недоступен (включая HTTP 401/403) или не допускает точного сравнения. |

Не называй coverage `verified` в любом другом случае. При `unavailable` report
path отсутствует. При `incomplete` и `stale` не передавай issues review engine.
При `unverified` передай exact report path только как `SONAR_HINTS_PATH`: это
не evidence и не источник готовых замечаний, а список мест для независимой
проверки current diff и кода.

## Использование workflow

- `review-gitlab-mr` вызывает contract с обязательным `HEAD_SHA` и передаёт
  `SONAR_EVIDENCE_PATH` в `review-mr` при `verified`; при `unverified` с
  полным валидным report передаёт только `SONAR_HINTS_PATH`.
- `aidd-fix-sonar` использует тот же entrypoint и JSON validation, но остаётся
  самостоятельным workflow: создаёт `RV-XXX`, принимает решение пользователя,
  исправляет код и отдельно подтверждает rescan. Его lifecycle не запускается
  из GitLab MR review.
