# Проверка сборки — 11 октября 2026

Среда: Apple Silicon, macOS 26, Xcode 27.0, Swift 6.4.

- 29 unit/integration tests: успешно, 0 ошибок.
- Xcode-проект: `xcodebuild … -scheme PlantUMLStudio -configuration Release build` — BUILD SUCCEEDED.
- Release .app: собран scripts/build.sh, включает PlantUML, исходники движка, Java и notices.
- Ad hoc подпись: `codesign --verify --deep --strict` — успешно.
- Запуск реального приложения: scripts/smoke.sh проверяет окно, привязку/геометрию редактора, Sequence, конструктор → исходник → renderer, Undo, Redo, сохранение, ER, SVG и PNG.
- Примеры Fixtures рендерятся официальным движком; invalid.puml вызывает диагностику.
- Автономная ER проверена без установленного Graphviz с `-Playout=smetana`.

Smoke-артефакты: `.build/Smoke/result.json`, `roundtrip.puml`, `diagram.svg`, `diagram.png`, `editor.png`, `window.png`.

Не проверено автоматизированно: полный сценарий пользовательских кликов, системные диалоги, поведение на macOS 14/15 и Intel. Ограничения описаны в KnownLimitations.md; этот отчёт не заявляет поддержку всего синтаксиса PlantUML.

## v0.2 / v0.3

v0.2: 39 XCTest прошли; release .app и GUI smoke с outline/palette/search/template undo/folding прошли. Реальные замеры записаны в docs/Performance-v0.2.json.

v0.3: 55 XCTest, 0 failures, 31.83 с. Дополнительно проверены Component declarations/containers/model/ranges/move/rename/delete safety, 6 шаблонов и SVG/PNG, text/structural diff/cardinality/order/ambiguity/large fallback, история и retention. Component declarations внутри note/comment не меняют Sequence-mode. GUI smoke включает историю, Component edit+undo и настоящее окно diff с двумя SVG; снимок .build/Smoke/diff-window.png. Это не полное покрытие всех keyboard/menu сценариев.
