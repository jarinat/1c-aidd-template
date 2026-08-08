# Ревизия agent layer Hermes (итерация B)

Дата: 2026-08-08
Спека: ../specs/2026-08-08-hermes-agent-layer-review-design.md
План: ../plans/2026-08-08-hermes-agent-layer-review.md

Объект: репозиторий `hermy-PROSYS-Avtolid`, ветка `experiment/edtpt-agent-layer`,
HEAD: `4384d6d22c865b058e5a3091361d4c5a68be9396`
(2026-08-07, «EDTPT-AI: harden renderer check and cross-platform tests»).
Файлы читаются из worktree
`C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid-agent-layer` (W).

Формат вердиктов: принять / доработать / выбросить; решение: engine / user.

## 0. Ограничения и фиксация объекта

- Оба worktree чистые (`status -sb` без изменений): основной — на
  `feature/MPLSYS-4793-edtpt-agent-layer` (HEAD `9f57043a5`, merge от
  2026-08-07), экспериментальный — на `experiment/edtpt-agent-layer`
  (`4384d6d22`).
- Ветка `feature/MPLSYS-4793-edtpt-agent-layer` ОТСТАЁТ от эксперимента на
  последний коммит `4384d6d22`: он содержится только в
  `experiment/edtpt-agent-layer`. Объект ревизии — вершина эксперимента
  (полная итерация B).
- Non-merge коммитов `EDTPT-AI:` — 12 (не 13, как предварительно оценивалось):
  `28ffe87ac, 3e968f43a, 44b736d95, 69351c62f, f966da8df, fa5978d02,
  49452739d, 48e9ccc4a, 189ac8a7a, b2458fcc0, 1e7a7c66b, 4384d6d22`.
  Смежный коммит пользователя: `3ba5e293d` «MPLSYS-4793: каталог .claude
  удален из .gitignore» — не Hermes, но входит в механику слоя (selective
  tracking) и учитывается в задачах 2 и 7.
- Затронутые зоны: `AGENTS.md`, `.agents/**`, `.claude/**`, `doc/ai/**`
  (изначально `docs/ai/**`, переименовано в `49452739d`), `tools/ai/**`,
  `.gitignore`, `.gitattributes`, корневой `CLAUDE.md` (создан в `69351c62f`,
  перемещён в `.claude/CLAUDE.md` в `fa5978d02`). Файлов вне ожидаемых зон
  не обнаружено; `.gitignore`/`.gitattributes` — инфраструктурные правки,
  детально проверяются в задачах 2 и 7.
- Состав слоя на вершине: 14 канонических skills `.agents/skills/mplsys-*`
  (+2 references), роль `.agents/roles/mplsys-implementer/ROLE.md`,
  14 адаптеров `.claude/skills/mplsys-*`, `.claude/agents/mplsys-implementer.md`,
  `.claude/CLAUDE.md`, `.claude/rules/mplsys/mplsys.md`, `doc/ai/README.md`,
  `doc/ai/project/{project-rules.template.md,project-rules.example.md}`,
  9 стандартов `doc/ai/standards/*`, `tools/ai/{mplsys-commit.sh,
  mplsys-render-claude-layer.sh,mplsys-validate-agent-layer.py}`,
  `tools/ai/tests/{run-selftests.sh,fixtures/sonar-issues.sample.json}`.

## 1. Испытания и отчёт Hermes

Найденные артефакты: каталог `.ai-eval/` (40 файлов, ignored) в worktree W.
Итоговый отчёт Hermes (15 пунктов по промпту) и матрица испытаний **как файлы
отсутствуют** — по-видимому, остались только в сессии Hermes.

Что фактически запускалось (по логам `.ai-eval/`):

| Испытание | Evidence | Статус |
|---|---|---|
| Discovery Codex (clean) | `codex-clean-discovery.txt`: Codex v0.144.5 видит слой, называет skills и commit-правило | подтверждено |
| Discovery Claude (clean) | `claude-clean-discovery.txt`: мост загружен, но на раннем этапе Claude НЕ мог перечислить skills из startup context (только `mplsys-code-review`) | подтверждено, с находкой |
| Discovery после переносов (`.claude`, `doc/ai`, новые skills) | `*-final.txt`, `claude-three-skills-startup-final.txt`, `codex-after-dotclaude-final.txt` | подтверждено |
| Сосуществование с личным слоем | `claude-dotclaude-local-coexistence.txt` (маркер из `CLAUDE.local.md` + корпоративные инварианты), `codex-personal-layer.txt` | подтверждено |
| Защита namespace | `namespace-conflict.txt`: validator (227 проверок) ловит подсадной `.claude/skills/mplsys-conflict-probe` | подтверждено |
| Commit helper | `commit1..4-dryrun.txt`: реальные dry-run прогоны | подтверждено |
| Языковая политика | `*-russian-policy-final.txt` | подтверждено |
| «Natural/explicit suites» обоих CLI (9 кейсов A–I) | `claude-natural-suite-full.md`, `codex-natural-suite.txt` и пр.: **routing-only** — «no actions were executed», PASS означает выбор правильного skill и правильных гейтов, а не исполнение сценария | подтверждено как routing, НЕ подтверждено как исполнение |
| Перекрёстное ревью hardening | `hardening-review.txt`, `hardening-final-review.txt`: содержательное критическое ревью (см. находки ниже) | подтверждено |

Известные проблемы, зафиксированные самим экспериментом и не имеющие
подтверждённого закрытия в логах:

- `str | None` в `mplsys-validate-agent-layer.py` поднимает минимальный Python
  до 3.10 без явной фиксации требования (hardening-final-review, пункт 1) —
  проверить фактическое состояние кода в задаче 6.
- Positive self-test `c-dynamic-skill` корректен только при динамическом
  обнаружении skills рендерером — требует подтверждения кода (задачи 5–6).
- Suites A–I запускались ДО переименования `docs/ai` → `doc/ai`; после
  финальных переносов повторялись только startup-discovery проверки, полный
  прогон suites не повторён.

Проверка «непересекаемых границ» промпта:

- `EDT-project-template` main не тронут: вершина `a9e5555` (2026-08-04, до
  старта Hermes). Ветка `feature/team-ai-tools` (итерация A) создана 31.07 —
  до эксперимента, Hermes ей не принадлежит.
- `1c-aidd-template` (донор) не тронут: история чистая.
- Push не выполнялся: `experiment/edtpt-agent-layer` и
  `feature/MPLSYS-4793-edtpt-agent-layer` существуют только локально.

## 2. Entrypoints

## 3. Standards

## 4. Skills

## 5. Мост и рендер Claude

## 6. Валидация и self-tests

## 7. Commit helper, fixtures и чистота коммитов

## 8. Сверка с итерацией A (mpl-*)

## 9. Не подтверждено испытаниями

Предварительный список по итогам задачи 1 (уточняется задачами 2–7):

1. Итоговый отчёт Hermes и матрица испытаний — файлов нет; полнота
   эксперимента восстанавливается только по `.ai-eval/` логам.
2. End-to-end исполнение сценариев промпта (реальное исправление запроса 1С,
   написание и прогон YAxUnit-теста, review синтетического diff с внесением
   правок address-review, обработка Sonar fixture с правками кода) — suites
   были routing-only; поведение skills при фактическом исполнении не
   проверялось ни на одном CLI.
3. Полный прогон suites после финальной структуры слоя (`doc/ai`,
   `.claude/CLAUDE.md`, 14 skills) — не повторялся; финальное состояние
   проверено только startup-discovery.
4. Прохождение полного `run-selftests.sh` на финальной вершине `4384d6d22` —
   лога нет (validator запускался, 227 checks, но единый «all pass» прогон
   self-tests не зафиксирован).
5. Сценарий «чистый разработчик» из чистого checkout только tracked-файлов —
   метод в логах не зафиксирован; discovery-логи есть, но воспроизводимость
   именно из чистого дерева не доказана.
6. Работоспособность слоя на Windows-машине разработчика (все helper'ы —
   bash/python; эксперимент шёл в Linux-контейнере Hermes).

## 10. Вход для дизайна самоулучшения

## 11. Сводка вердиктов и доработки для подпроекта 2
