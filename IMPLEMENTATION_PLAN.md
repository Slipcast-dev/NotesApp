# NotesApp: план перехода к file-first Markdown

Обновлено: 2026-07-23. Минимальная система: macOS 13 Ventura.

## Неподвижные архитектурные правила

- Единственный источник истины — обычные UTF-8 Markdown-файлы и вложения внутри выбранного vault.
- SQLite может содержать только удаляемые кэши и индексы; удаление `.notesapp/index.sqlite` не должно удалять пользовательские данные.
- В `.md` никогда не записывается RTF. Старая SQLite/RTF-база остаётся нетронутой до явной, резервируемой миграции.
- Vault совместим с существующей структурой Obsidian: приложению не требуется конвертировать папку перед открытием.
- Запись содержимого атомарна; внешние изменения и конфликты не должны молча перезаписываться.
- Windows-исходники сохраняются. Новые функции macOS не должны требовать сетевых зависимостей для сборки.

## Аудит исходного состояния

- SwiftPM-порт уже собирает `NotesCore` и `NotesApp`; target закреплён на macOS 13.
- `AppStore` считает SQLite источником заметок, а `MarkdownNoteStore` создаёт имена `note-000001.md`.
- AppKit-редактор сериализует `NSAttributedString` в RTF; это значение затем попадало внутрь `.md` после заголовка. Этот путь должен быть исключён из нового приложения.
- Поиск выполнялся полным чтением заметок в UI-store и не был перестраиваемым индексом.
- Ссылки разрешались только по точному совпадению заголовка и не учитывали путь, heading, block ID или alias.
- Публикация macOS-порта подготовлена как черновой prerelease `v2.0.0-beta.1`; Windows-исходники и их portable-релиз сохраняются рядом.

## Этапы и зависимости

### Phase 1 — Vault и файловая модель — ЗАВЕРШЁН

- [x] `Vault`, `VaultItem`, `NotePath`, `VaultNote`, настройки vault.
- [x] `VaultFileService`: обход дерева, UTF-8 read/write, create/rename/move/duplicate/trash, collision checks, atomic writes.
- [x] `SecurityScopedBookmarkStore`: восстановление последнего vault и список недавних vault.
- [x] `FileChangeMonitor`: рекурсивное наблюдение папок, debounce и обновление после внешних изменений.
- [x] `VaultStore`: Markdown-файлы определяют состояние; автосохранение и явное разрешение конфликтов.
- [x] UI дерева, internal drag-and-drop, Finder, выбор/создание vault, настройки новых заметок/вложений.
- [x] Source editor сохраняет только Markdown; старый RTF-путь больше не используется точкой входа.
- [x] Файловые integration/conflict/Unicode tests и исполняемый smoke test.
- [x] Сборка, запуск, `--verify`, `git diff --check`.

Зависимость: нет. Блокирует все следующие этапы.

### Phase 2 — Безопасная миграция RTF → Markdown — ЗАВЕРШЁН

- [x] `MigrationService`: read-only detection, dry-run, SQLite backup API, per-note crash-safe manifest, idempotency, recoverable undo и JSON/Markdown отчёт.
- [x] Преобразование RTF font traits/headings/lists/checklists/box tables/links в Markdown.
- [x] Понятные collision-safe имена, YAML tags/dates/legacy metadata; исходные данные не удаляются.
- [x] UI в Settings и unit/integration/smoke tests на сгенерированной реальной RTF/SQLite-схеме.

Зависимость: Phase 1.

### Phase 3 — Единый Markdown AST — ЗАВЕРШЁН

- [x] Единые `MarkdownParser`, source-ranged AST, `MarkdownRenderer` и `MarkdownLinkExtractor` для CommonMark/GFM-совместимого синтаксиса и расширений vault.
- [x] H1–H6, emphasis/strong/combined/strike/highlight, nested lists/tasks, quotes/callouts, inline/fenced code, tables, rules, footnotes/comments.
- [x] Markdown links/images, inline/block math, Mermaid language blocks, wikilinks/embeds/aliases/heading/block targets и typed YAML frontmatter.
- [x] Feature conformance, golden HTML, semantic round-trip и smoke tests.

Зависимость: Phase 1. Блокирует редактор, индекс, links, Canvas и плагины.

### Phase 4 — Markdown-редактор — В РАБОТЕ

- [x] Source, полностью отрисованный визуальный Preview и Reading с общей AST-моделью; таблицы в Preview показываются сеткой, а не Markdown-символами.
- [x] Highlighting, mode selection preservation, native undo/redo/find/replace и spellcheck.
- [x] Auto-pairs, Markdown formatting commands, clipboard/file DnD и table/task insertion.
- [x] Word-подобный визуальный редактор таблиц: ячейки/шапка, строки, столбцы, перестановка, выравнивание, Enter/Tab-навигация и безопасная запись обратно в Markdown.
- [x] Интерактивные Reading checkboxes, включая пустые/вложенные задачи; изменение флажка сохраняется как `[ ]`/`[x]` и проходит через обычное автосохранение.
- [x] Полная RU/EN-локализация основных экранов vault, редактора, таблиц, настроек, меню, конфликтов, индексации и миграции.
- [x] Link navigation, indexed outline и word/character counters.
- [ ] Контекстное скрытие Markdown markers, wikilink autocomplete/slash palette, hover preview и полное per-tab scroll restoration.
- [ ] Общий `CommandRegistry` для toolbar/menu/context menu/palette/hotkeys.

Зависимость: Phase 3.

### Phase 5 — Перестраиваемый индекс — ЗАВЕРШЁН

- [x] Actor-isolated `MetadataIndex`/`SearchIndex`, SQLite cache + FTS5 и versioned additive schema.
- [x] Инкрементальная фоновая индексация headings/blocks/links/tags/aliases/properties/tasks/attachments.
- [x] Rename/move/delete reconciliation, progress/cancel, rebuild после удаления и quarantine/rebuild после повреждения.

Зависимость: Phase 1 и Phase 3.

### Phase 6 — Links, backlinks, graph и search — В РАБОТЕ

- [x] `LinkResolver`, path/title/relative wiki/Markdown links, heading/block targets, ambiguity и создание unresolved note.
- [x] Backlinks/outgoing с контекстом и UI-переходом.
- [x] FTS/phrase/regex/boolean и `path/file/tag/property/task/line/block` operators, snippets/highlighting.
- [ ] Atomic link rewrite после rename/move, unlinked mentions и переход cursor к heading/block.
- [ ] Local/global graph, saved/embedded search и Quick Switcher.

Зависимость: Phase 5.

### Phase 7 — Attachments и properties — В РАБОТЕ

- [x] `AttachmentService`: arbitrary media/PDF, paste/DnD/file chooser, configurable locations, embeds/width/PDF fragment syntax и missing/orphan audit.
- [x] Typed YAML AST, Reading properties panel и indexed property search.
- [x] Attachment unit/smoke tests.
- [ ] Visual property mutation editor, type registry UI и transactional bulk rename.

Зависимость: Phase 3 и Phase 5.

### Phase 8 — Workspace и core tools — ОЖИДАЕТ

- [ ] `WorkspaceStore`, tabs/splits/pop-outs/pinning/history/layout restoration.
- [ ] Bookmarks, daily notes, templates, unique/random/composer/recovery/local history.
- [ ] Palette/hotkeys, auxiliary views, recents/import/export/URI/Services.

Зависимость: Phase 4–7.

### Phase 9 — Canvas и Bases — ОЖИДАЕТ

- [ ] Совместимый `.canvas` JSON и полноценный бесконечный canvas.
- [ ] `.base`/embedded bases, views/filters/sort/group/formulas/computed columns/property edit.

Зависимость: Phase 3, Phase 5 и Phase 8.

### Phase 10 — Plugin API — ОЖИДАЕТ

- [ ] Внутренние функции переведены на manifest/versioned `Plugin API`.
- [ ] Commands/editor/views/file events/metadata/settings/permissions и crash isolation.
- [ ] Compatibility/signing/update/plugin manager/themes/design tokens.

Зависимость: стабильные Phase 1–9.

### Phase 11 — Sync, history и publish/export — ОЖИДАЕТ

- [ ] Проверенная работа vault в iCloud Drive и `HistoryService`.
- [ ] `SyncService`: offline queue, E2EE, conflicts, history/recovery/selective sync/devices/integrity/key rotation.
- [ ] Static publish выбранных заметок с navigation/backlinks/search/graph/themes/exclusions/preview.

Зависимость: стабильная файловая модель и history.

## Принятые решения

1. Phase 1 вводится рядом с legacy SQLite-кодом. Точка входа приложения переключается на `VaultStore`; legacy сервисы остаются read-only-кандидатами для Phase 2.
2. Стандартный новый vault хранится отдельно от legacy `Data`, чтобы не переинтерпретировать файлы с RTF как корректный Markdown.
3. Никаких новых внешних Swift dependencies: это сохраняет offline-сборку на текущем SwiftPM/CommandLineTools окружении.
4. Дерево строится из файловой системы при каждом согласованном refresh. `.notesapp` скрыт и содержит только воспроизводимые метаданные/настройки.
5. При конфликте несохранённая версия остаётся в памяти, дисковая показывается как альтернативная; пользователь явно выбирает reload или overwrite.

## Журнал проверок

- 2026-07-23, Phase 1–3: `./script/test_with_command_line_tools.sh` — пройден (file-first CRUD/conflict/manifest, RTF migration/backup/idempotency, AST/link/render smoke).
- 2026-07-23: `./script/build_and_run.sh --verify` — пройден; SwiftPM на данной установке CLT не находит `PlatformPath`, предусмотренный fallback успешно собрал app bundle и проверил процесс.
- 2026-07-23: `git diff --check` — пройден без ошибок.
- 2026-07-23, Phase 4–7 increment: повторный `./script/test_with_command_line_tools.sh` — пройден; FTS phrase/filters/backlinks/incremental skip и attachment audit включены.
- 2026-07-23, Phase 4–7 increment: повторный `./script/build_and_run.sh --verify` — пройден после UI/editor/index integration.
- 2026-07-23, Word-like tables/tasks + RU/EN: `./script/test_with_command_line_tools.sh` — пройден; проверены Unicode offsets, пустые/вложенные task markers, toggle round-trip, изменение строк/столбцов/выравнивания и повторный разбор таблицы.
- 2026-07-23, release candidate: offline smoke-наборы пройдены; Intel `.app` собран с минимальной системой macOS 13.0, проверены ad-hoc подпись, запуск и целостность ZIP.
- Полный `swift test` требует установленного полного Xcode; XCTest suites добавлены и дублируются исполняемым offline smoke-набором для текущего окружения.
