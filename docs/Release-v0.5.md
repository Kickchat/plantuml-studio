# PlantUML Studio v0.5 — Semantic Constructor

Development version 0.5.0, build 5, for Apple Silicon / macOS 14+. Source remains the single document model. The existing parser supplies every source range; `SemanticStructure` is a projection of its nodes, not an independent parser. The official renderer and layout engine are unchanged.

## Delivered behaviour

- Sequence has Participants and Scenario sections, readable names/types/color indicators, message text plus actual sender/receiver (including reverse arrows), nested control blocks and individually selectable `else` branches. The initial branch is a presentation of the block's condition, not a duplicate source node.
- ER has collapsible entities with attribute names, types, explicit stereotypes/mandatory markers, and a separate relationship section with both endpoint cardinalities. An attribute named `id` is never treated as a primary key automatically.
- Native contextual forms edit supported properties. Missing aliases, labels, colors and attribute types can be added. Display-name edits preserve reference identities; alias changes update known message/relation/activation/note targets while leaving literal note text intact. Quoted declarations without aliases receive a unique alias when needed to safely rename them.
- The add menu respects diagram type and selected context. Messages and blocks can be added to a specific branch. Entity attributes can be added individually or through a native multi-attribute form. Supported rows have contextual edit, duplicate, delete, move and source-navigation actions; prohibited moves are disabled.
- Declaration deletion offers Cancel or explicit deletion with dependent messages/relationships/notes/activations. Unknown references block this operation and offer source navigation. Deleting a branch removes that branch's header/body while retaining adjacent branches and the block delimiter.
- Diagram Settings contains title, simple global autonumber and four whitelisted single-line skinparams: backgroundColor, defaultFontName, defaultFontSize and sequenceMessageAlign. Arbitrary skinparam/style blocks remain opaque and unchanged. Multiple or parameterized autonumber commands are not simplified to a boolean.
- Search uses object titles, endpoint display names and aliases, retaining the ancestors of nested matches. ⌘-click preserves existing multi-selection operations.
- Expansion, section collapse, property collapse, query, selected object, layout and constructor visibility belong to the document and survive tab switching. Source edits reconcile stable IDs, including unambiguous reordering; identical ambiguous nodes are never matched by guessing.
- Constructor selection reveals code and requests exact SVG navigation. Code selection reveals tree ancestors. SVG mapping requires a unique source match, and highlighting additionally requires a unique visual match. Duplicate labels do not select a guessed object.
- On invalid code the last valid tree remains visible with an outdated-state notice, and source-changing actions are disabled. Every range operation checks node freshness; UI field reads are bounded during model replacement.
- Panel widths and property height are adjustable through native splitters. The constructor can be hidden independently. Preview starts fitted to the window; Fit to Width/Window responds to resizing, manual zoom survives rendering, and scrolling/Alt-drag pans the diagram. Light/Dark/System use existing design tokens.

## Verification

Acceptance run: 75 Swift tests and 10 release-script tests, Release build and GUI smoke. The DMG is verified both by checksum and by mounting read-only and checking the embedded bundle/signatures.

`./scripts/test.sh`, `./scripts/build.sh`, `./scripts/smoke.sh`, and `python3 -m unittest discover -s scripts/tests -v` are the verification entry points. The constructor suite covers semantic labels, nested ALT/ELSE/OPT/LOOP/PAR, ER attributes/cardinalities, forms and missing fields, branch insertion/deletion, dependency guards, quoted identities, comments, UTF-16/CRLF, unchanged unknown settings, stale rows and stable identities. The large case has 1,500 blocks and 1,500 messages and checks a five-second budget for parsing/projection/reconciliation, without running an expensive layout benchmark.

The in-process GUI smoke exercises real windows, editor selection, both navigation directions, selection/expansion after edits and Undo/Redo, invalid-code recovery, implicit participant selection without modifying source, declaration creation, native themes, constructor visibility and responsive Fit. Existing save/render/export/history/templates/component/diff/appearance checks remain included.

Screenshots: [Light](Screenshots/semantic-light.png), [Dark](Screenshots/semantic-dark.png). A repeatable generic workflow scenario is in [Fixtures/semantic-workflow.puml](../Fixtures/semantic-workflow.puml).

## Boundaries

The fixture is a fictional workflow with generic participants and nested control blocks.

Only syntax already recognized by the existing parser (plus the four explicit global settings) is exposed as editable forms. Unsupported arrow decorations, preprocessor constructs and arbitrary styles remain in code. Conservative alias/deletion/move guards may require manual source editing when unknown references, comments or structural boundaries prevent a safe change. Explicit participant `order` values remain editable as properties; source declaration order cannot override those PlantUML values.

Implicit participants are shown as objects; selection alone never changes code. An explicit declaration is required to edit their display/type/color. SVG matching remains conservative when labels repeat, split into multiple text spans, or cannot be uniquely mapped.

The DMG contains a locally signed development app, not a Developer ID/notarized production release. Automatic delivery still requires Apple/Sparkle credentials and a public repository as described in [RELEASING.md](../RELEASING.md). Bundle ID, saved preferences, session and history paths are unchanged.

Syntax references: [official Sequence diagrams](https://plantuml.com/sequence-diagram), [official Information Engineering diagrams](https://plantuml.com/ie-diagram).
