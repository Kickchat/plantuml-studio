# PlantUML Studio v0.3

Ветка release/v0.3 создана от release/v0.2 (af778f6). Слияние в main не выполнено.

## Что добавлено

ComponentModule: типизированные ComponentNode / ComponentRelationship, родительский контейнер, ComponentType (component, interface, package, node, database, cloud, frame, folder), ComponentContract, безопасное перемещение в контейнер / корень, шесть шаблонов. Общие ranged primitives в PlantUMLCore; ComponentSyntax отдельно от Sequence/ER grammar. Shared SourceDocument.reconcile, undo, Document, Renderer и Constructor не дублируются. Supported declarations включают quoted name / as alias, bracket component, () interface, цвет, stereotype, обычные стрелки и dotted/solid links. Нестандартная грамматика сохраняется как unsupported.

Constructor: создание элементов/связей, изменение type/name/alias/color/stereotype/endpoints/line/label, глобальный rename ссылок, nested containers, добавление компонента внутрь, перемещение между контейнерами, охраняемое удаление. Удаление контейнера с внешними ссылками на его потомков запрещено.

Visual Diff: два выбранных файла, текущий / последняя сохранённая версия, два открытых документа; общая прокрутка aligned text rows; добавленные, удалённые и изменённые строки; переходы prev/next; структурные изменения с точными диапазонами; две read-only SVG рядом, общий zoom и переход/подсветка при однозначном соответствии. Invalid/mixed kinds — text-only. Повторяющиеся сообщения/отношения — ambiguity; неизвестные строки — text fallback. Никакого преобразования исходника при сравнении.

ModuleContract: распознавание, parse, identity fields, property fields, validation, rename, diff. SequenceContract / ERContract / ComponentContract сохраняют собственные vocabulary и модели. Общий matching учитывает diagram kind, element kind, scoped identifiers / endpoint identities и ancestry; неоднозначные группы не сопоставляются по порядку. Изменения атрибутов и cardinality сопоставляются в контексте сущности; порядок сравнивается только среди однозначно сопоставленных элементов.

History: atomic JSON в Application Support/PlantUML Studio/History, SHA256 ключ нормализованного пути; дата/UUID/source; сохранение при успешном сохранении файла, consecutive deduplication; настройки по умолчанию 30 snapshots / 20 МБ на файл. Сравнить, открыть копию, restore с подтверждением. История не зависит от Undo, восстановление редактирует текущий документ и требует обычного сохранения для изменения файла на диске.

## Ограничения

Подмножество официальной грамматики: multiline declaration headers, advanced arrow decorations и inline container bodies остаются unsupported или запрещают конструктор. Database-only документ неоднозначен с Sequence: выберите Component вручную. Implicit endpoints без явного объявления отображаются renderer, но не создаются как вымышленные editable declarations. Общий parser хранится в Core во избежание циклической зависимости Swift Package; typed semantics/operations/contracts/templates — в отдельных модулях.

Diff консервативен: переименование идентификатора или перемещение между разными scoped contexts может показываться как remove/add; повторяющиеся структуры помечаются ambiguous. Соответствие не выводится только из похожего текста или ближайшей позиции. Стрелки без уникальной SVG-подписи не подсвечиваются предположительно. По умолчанию SVG zoom общий, прокрутка каждой SVG отдельная. Текстовый LCS ограничен 2000 строк на сторону; большие документы используют exact prefix/suffix text fallback (он менее точен в середине).

History лимиты на файл, применяются при следующем сохранении; очень большой snapshot, превышающий лимит, не сохраняется в истории. History пока без encryption/cloud/synchronization. PNG logo берётся из текущего Assets/image.png (fallback paths поддерживаются), без изменения исходного bitmap.

## Проверка

./scripts/test.sh — регрессия v0.1/v0.2, все shapes, nested model/ranges, component rename/move/delete safety, bracket refs, все Component-шаблоны реальным renderer, SVG/PNG; text/structural diff, повторяющиеся сообщения, ER cardinality, ordering, large fallback, history/dedup/count/bytes.

./scripts/build.sh — release .app, JRE/PlantUML внутри, ICNS, ad-hoc signing.

./scripts/smoke.sh — реальные SwiftUI/AppKit/WKWebView окна, Editor geometry/folding, constructor/undo/save/history/ER/export/component/diff-window. Screenshots: .build/Smoke/window.png, editor.png, diff-window.png. Это smoke, не полное XCTest UI покрытие всех меню и keyboard preferences.

Слияние предлагается после просмотра обоих release commits и запуска .app; automatic merge отсутствует.

Финальная проверка на текущем Mac: 55 XCTest, 0 failures (31.83 с); включая регрессию «component внутри Sequence-note». Release Xcode build, GUI smoke и codesign --verify прошли на финальном исходнике. Логи остаются локально в .build/release-tests.log / release-xcode.log; smoke result — .build/Smoke/result.json.

Официальные источники синтаксиса: https://plantuml.com/sequence-diagram, https://plantuml.com/ie-diagram, https://plantuml.com/component-diagram (использование согласовано пользователем вместо отсутствующего вложенного гайда).
