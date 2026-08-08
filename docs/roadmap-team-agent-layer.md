# Roadmap: командный agent layer MPL Systems (mpl-*)

Обновлено: 2026-08-08. Это верхнеуровневый статус-документ мета-задачи;
обновляй его при каждом существенном шаге. Детальные артефакты — рядом:
спека `specs/2026-08-08-hermes-agent-layer-review-design.md`, план
`plans/2026-08-08-hermes-agent-layer-review.md`, отчёт ревизии
`reviews/2026-08-08-hermes-agent-layer-review.md`, постановка эксперимента
`../prompts/hermes-edt-corporate-agent-layer.md`.

## Цель

Универсальная командная AI-обвязка для 1С/EDT-проектов: работает с Claude
Code и Codex, расширяется проектным и персональным слоями, не навязывает
личный workflow (AIDD остаётся личным слоем). Доставка — через
`EDT-project-template`. Позже, после стабилизации, — общий командный workflow
поверх слоя.

## Архитектура (принято)

- Namespace `mpl-*`; три слоя: корпоративный → проектный (`doc/ai/project`) →
  персональный (gitignored: `AGENTS.local`/`.agents/local/`, `CLAUDE.local.md`,
  личный `.claude/`).
- Один source of truth: канонические skills `.agents/skills/mpl-*` (Codex,
  стандарт Agent Skills), тонкие Claude-адаптеры `.claude/skills/mpl-*`
  генерируются `tools/ai/mpl-render-claude-layer.sh`; мост
  `.claude/CLAUDE.md` = `@../AGENTS.md` (Claude не читает AGENTS.md нативно).
- Инварианты держит код, не проза: `tools/ai/mpl-validate-agent-layer.py`,
  self-tests, CI-job «Проверка agent layer».

## Сделано

1. **Ревизия итерации B (Hermes)** — отчёт в `reviews/`, все решения приняты.
   Итерация A (`mpl-*` от 31.07) признана устаревшей и удалена.
2. **Слой в шаблоне**: `EDT-project-template`,
   ветка `origin/feature/team-ai-tools-v2` — 6 коммитов (338571c..8321fd4:
   entrypoints+standards, skills+адаптеры, tools, examples+миграция, CI,
   Codex-на-Windows). В `main` НЕ мержить до решения по итогам наблюдений.
3. **Установка в MBS**: ветка `feature/team-ai-tools` (merge 3eaae4204 от
   origin/develop, конфликт только в `.gitignore`). Личный AIDD-слой
   мигрирован: `AGENTS.md` → `.agents/local/instructions.md`,
   `.claude/CLAUDE.md` → `CLAUDE.local.md`. Проверки: validator 515 OK,
   render --check OK, self-tests 89/0, Claude discovery 13 skills.
4. **Пилот MPLSYS-4793 (успех, 2026-08-08)**: Sonnet-агент через слой сделал
   два изменения (7caddf397 — ошибка в ЖРС при ненайденном контрагенте;
   353eba90d — каскад индекса организации 5→4→3), YAxUnit зелёные,
   Codex сам выбрал `mpl-code-review`, выдержал read-only, единственный
   minor отклонён по evidence (штатный стиль EDT).

## Бэклог доработок слоя (по находкам пилота)

- [ ] Документировать в `doc/ai/README.md`: зависимость MCP `1c-rsv` от
      «проект открыт в запущенном EDT» (симптом: `Project not found`),
      порядок действий при недоступности.
- [ ] Документировать композицию с личным слоем: личный `PreToolUse`-hook
      может блокировать корпоративный workflow (Write/Edit в `src/**`) —
      это осознанная защита, но нужна инструкция «что делать агенту и
      человеку» при таком блоке.
- [ ] Косметика: русский вывод validator в cp1251-консоли — кракозябры
      (chcp/encoding или ASCII-вывод).

## Следующие шаги

1. **MBS**: push `feature/team-ai-tools` в origin и MR в `develop` — по
   решению владельца (коммиты MPLSYS-4793 поедут вместе со слоем; при
   необходимости разделить — cherry-pick).
2. **Наблюдение**: 1-2 задачи на других проектах/разработчиках через слой
   (установка по `doc/ai/README.md`, раздел «Обновление существующего
   проекта с личным слоем»).
3. **Бэклог** (выше) — очередной коммит в `feature/team-ai-tools-v2`.
4. **MR слоя в `main` шаблона** — после успешных наблюдений.
5. **Подпроект 4 — механизм самоулучшения**: спроектировать проектную
   «копилку правил» (стандартизированный пост-задачный артефакт с
   наблюдениями/трением → централизованный разбор и курирование ТОЛЬКО
   владельцем → правила в `doc/ai/project` или доработки слоя). Материал
   пилота — готовый тестовый кейс. Отдельный brainstorming.
6. **Позже**: стабильный командный workflow поверх слоя (кандидаты-референсы:
   AIDD, Superpowers-паттерны) — отдельное решение, не раньше стабилизации.

## Как продолжать работу по теме

- Сессия в MBS: контекст подтянется из памяти проекта (Claude Code auto
  memory, запись `team-agent-layer-pilot`) — просто скажи «продолжаем
  командный agent layer, см. roadmap» и укажи этот файл.
- Сессия в шаблоне/мета-репо: начинай с этого файла.
- Правки слоя — только на `feature/team-ai-tools-v2` шаблона, с прогоном
  validator + render --check + self-tests до коммита; в проекты — merge
  ветки шаблона.
