# Changelog

## 0.5.0 — Development build

- Semantic Sequence/ER constructor with object names, directions, branches, attributes and relationships; separate diagram settings.
- Contextual property forms, object search, branch insertion/deletion and explicit dependency-aware deletion.
- Minimal source edits preserve comments, unknown statements and UTF-16/CRLF; stable identities retain selection and expanded groups.
- Constructor/code/SVG navigation, conservative matching, last-valid-state recovery and safe stale-range checks.
- Adjustable/hideable panels and properties, responsive Fit to Window/Width, retained zoom and native Light/Dark themes.
- Installable Apple Silicon DMG with bundled Java/PlantUML.
- Fictional demo scenarios with generic participants in fixtures, tests, documentation and screenshots.

## 0.4.0 — Development build

- Sparkle 2.10: Stable HTTPS appcast, signed feeds and EdDSA archives, built-in update UI, background checks and menu command.
- Update installation waits for saving or explicitly discarding unsaved diagrams; cancellation postpones installation.
- Version.json synchronizes application version/build with release tags and signed appcasts.
- Pull-request verification and gated Developer ID/notarized release workflow, public GitHub Releases with a signed latest-release feed.
- Source publication, MIT license and release documentation.
- Synchronous Undo callback compatible with the macOS SDK used on CI.

## 0.3.1

- Centralized native Light, Dark and System themes, persisted Appearance settings.
- Redesigned panels and syntax colors; theme switching preserves editor state and SVG.
- Fixed code viewport overlap with line numbers.

## 0.3.0

- Component constructor, conservative structural/SVG diff and local saved-version history.

## 0.2.0

- Outline/navigation, command palette, templates, search/replace, editor assistance and preview zoom/pan.
- Cancellable rendering and performance benchmarks.

## 0.1.0

- Initial native macOS editor, Sequence/ER constructors, local PlantUML renderer, files and Undo/Redo.
