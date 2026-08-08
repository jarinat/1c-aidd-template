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

## 2. Entrypoints

## 3. Standards

## 4. Skills

## 5. Мост и рендер Claude

## 6. Валидация и self-tests

## 7. Commit helper, fixtures и чистота коммитов

## 8. Сверка с итерацией A (mpl-*)

## 9. Не подтверждено испытаниями

## 10. Вход для дизайна самоулучшения

## 11. Сводка вердиктов и доработки для подпроекта 2
