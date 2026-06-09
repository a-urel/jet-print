# Feature Specification: Flutter Library + Playground App Scaffold

**Feature Branch**: `001-flutter-library-scaffold`  
**Created**: 2026-06-05  
**Status**: Draft  
**Input**: User description: "create flutter lib: create empty flutter app that includes both widget library and a playground app for the library. use shadcn ui library in the project(s). placeholders are acceptable in this first iteration. just make sure the architecture is clean and maintainable from day one."

## Clarifications

### Session 2026-06-05

- Q: How should the monorepo be structured so the playground app depends on the library like an external consumer? → A: Dart pub workspaces (built-in `workspace:` resolution; library and playground app as separate sibling packages sharing one lockfile, no extra tooling).
- Q: How should the architectural layer seams (domain, rendering, designer/UI) be physically realized in this first iteration? → A: As internal directories under the library's private source area (e.g., `src/domain`, `src/rendering`, `src/designer`), with the inward-dependency rule enforced by tests and lint rules — not as separate packages.
- Q: What should the playground app's primary target platform be for this iteration? → A: macOS desktop (other platforms may be enabled later).
- Q: Which shadcn UI implementation should the projects use? → A: The community `shadcn_ui` Flutter package (provides themed components and the ShadApp/ShadTheme pipeline).

## User Scenarios & Testing *(mandatory)*

<!--
  This is a foundation/scaffolding feature. The primary "users" are developers:
  downstream consumers who will embed the library, and contributors who will
  extend it. Stories are ordered so that each delivers a standalone, demonstrable
  slice of the clean, maintainable foundation.
-->

### User Story 1 - Consume the library through its public API (Priority: P1)

A developer building a separate Flutter application wants to depend on the widget
library and place one of its components on screen, importing only the library's public
entry point and never reaching into its internal source. They add the dependency, import
the single public library file, drop a placeholder component into their widget tree, and
it renders.

**Why this priority**: The library is the product. If it cannot be consumed cleanly
through a deliberately minimal public API — with internals hidden — nothing else matters.
This story is the foundation every other capability builds on.

**Independent Test**: Can be fully tested by adding the library as a dependency in a
throwaway consumer (the playground app counts), importing only the public library file,
referencing a placeholder component, and confirming it builds and renders without ever
importing a path under the library's private source directory.

**Acceptance Scenarios**:

1. **Given** a Flutter app that declares a dependency on the widget library, **When** the developer imports only the library's public entry point and adds a placeholder component to the widget tree, **Then** the app compiles and the component renders on screen.
2. **Given** the library package, **When** a consumer attempts to reference a symbol that is internal (not intentionally exported), **Then** that symbol is not reachable through the public entry point.
3. **Given** the library package, **When** its public surface is inspected, **Then** every exported symbol is intentional and documented, and no host-application code, global singleton, or app-specific assumption is required to use it.

---

### User Story 2 - Run the playground app and see shadcn-styled output (Priority: P2)

A contributor checks out the repository, runs the playground app, and sees the library's
placeholder component rendered inside an application shell that is themed with the shadcn
UI design system. This proves the playground app exercises the library exactly as a real
consumer would and that the shadcn theming foundation is wired correctly.

**Why this priority**: A playground app that consumes the library as a real downstream app
keeps the public API honest and gives contributors a live surface to validate changes.
Establishing shadcn theming now prevents a costly retrofit later. It depends on Story 1's
consumable library existing.

**Independent Test**: Can be fully tested by launching the playground app on at least one
target platform and confirming the placeholder component appears within a shadcn-themed
application shell, with the app consuming the library only through its public API.

**Acceptance Scenarios**:

1. **Given** a freshly cloned repository, **When** a contributor runs the playground app, **Then** the app launches and displays the library's placeholder component inside a shadcn-themed shell.
2. **Given** the playground app, **When** its source is inspected, **Then** it references the library only through the public entry point and contains no duplicated copy of the library's internals.
3. **Given** the running playground app, **When** the contributor switches the shadcn theme (e.g., light/dark or a different color scheme), **Then** the placeholder component reflects the theme change, demonstrating the theming pipeline is live.

---

### User Story 3 - Trust the foundation via a passing, layered test suite (Priority: P3)

A contributor runs the project's automated checks and sees a green, meaningful test suite
covering the scaffold: the library's public API, the layer boundaries, and the placeholder
component. New contributors can therefore add features test-first with confidence that the
seams already exist.

**Why this priority**: The constitution makes Test-First non-negotiable and requires layer
boundaries to be independently testable. Establishing the test harness and layer seams in
the scaffold is what makes the architecture "maintainable from day one" rather than an
aspiration. It builds on Stories 1 and 2.

**Independent Test**: Can be fully tested by running the project's test command and
confirming all tests pass, including at least one test per architectural layer seam and a
test asserting the placeholder component renders.

**Acceptance Scenarios**:

1. **Given** a clean checkout, **When** a contributor runs the project's automated checks, **Then** static analysis reports no errors and all tests pass.
2. **Given** the scaffold, **When** the test suite is inspected, **Then** it includes a test exercising the library's public API and at least one test per defined layer seam (domain, rendering, designer/UI presentation).
3. **Given** the placeholder component, **When** its widget test runs, **Then** it confirms the component builds and renders without depending on the playground app.

---

### Edge Cases

- What happens when a consumer's app uses a different (but supported) version of the shadcn UI dependency than the library expects? The dependency constraints must make compatibility explicit rather than failing at runtime.
- How does the scaffold behave on a platform the playground app does not target? The supported target platforms must be stated, and unsupported platforms must fail fast with a clear message rather than render incorrectly.
- What happens when a contributor accidentally adds a dependency from the domain layer onto the rendering or UI layer? The architecture's inward-pointing dependency rule must be detectable (e.g., via tests or analysis) rather than silently allowed.
- What happens when a new contributor clones the repo and runs setup? The path from clone to running playground app and passing tests must be documented and reproducible.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The project MUST contain a reusable widget library, distributable as a standalone package, that downstream Flutter applications can depend on without modification.
- **FR-002**: The project MUST contain a separate playground (sample) application that consumes the widget library solely through the library's public API.
- **FR-003**: The widget library MUST expose a deliberately minimal public API through a single public entry point; all internal types MUST reside in a private source area and MUST NOT be reachable by consumers.
- **FR-004**: The widget library MUST ship at least one placeholder component that consumers can render, serving as the proof-of-consumption example.
- **FR-005**: Both the library and the playground app MUST integrate the `shadcn_ui` Flutter package as the shadcn UI design system, with the playground app demonstrating shadcn theming (via the ShadApp/ShadTheme pipeline) applied to the placeholder component.
- **FR-006**: The library MUST establish the architectural layer seams (domain/report model, rendering/layout, designer/UI presentation) as distinct, independently testable units realized as internal directories under the library's private source area (e.g., `src/domain`, `src/rendering`, `src/designer`), even where their first-iteration contents are placeholders.
- **FR-006a**: The repository MUST be organized as a Dart pub workspace in which the widget library and the playground app are separate sibling packages sharing a single lockfile, so the playground app resolves the library the same way an external consumer would.
- **FR-007**: Dependencies between layers MUST point inward toward the domain model; the domain layer MUST NOT depend on rendering or UI layers, and this rule MUST be verifiable.
- **FR-008**: The scaffold MUST include automated tests covering the library's public API, each layer seam, and the placeholder component, and these tests MUST pass on a clean checkout.
- **FR-009**: The scaffold MUST include static analysis configuration, and a clean checkout MUST report no analysis errors or warnings (per Constitution §VI, which mandates zero analyzer warnings).
- **FR-010**: The repository MUST document how to install dependencies, run the playground app, and run the test suite, such that a new contributor can reproduce all of the above from the documentation alone.
- **FR-011**: The widget library MUST be self-contained and MUST NOT depend on playground-app code, host-application code, or app-specific global state.
- **FR-012**: The scaffold MUST declare an initial library version and dependency version constraints (including shadcn UI and the framework) explicitly, establishing the baseline for future semantic-versioned releases.

### Key Entities *(include if feature involves data)*

- **Widget Library Package**: The reusable, publishable unit that is the product. Holds the public API surface, the private internals, and the placeholder component. Has a declared version and explicit dependency constraints.
- **Public API Surface**: The set of intentionally exported, documented symbols that consumers may use; the contract that the playground app and future consumers exercise.
- **Playground (Sample) Application**: A consumer of the library that renders the placeholder component within a shadcn-themed shell; exists to keep the public API honest and to provide a live validation surface.
- **Placeholder Component**: The minimal example widget exported by the library, used to prove end-to-end consumption and theming.
- **Architecture Layer Seam**: A defined, independently testable boundary (domain, rendering, designer/UI) whose dependency direction is constrained inward; first-iteration contents may be placeholders.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can add the library as a dependency and render the placeholder component in a separate app by importing only the public entry point, with zero references to the library's internal source.
- **SC-002**: A new contributor can go from a fresh clone to a running playground app showing the shadcn-themed placeholder component in under 10 minutes using only the documented steps.
- **SC-003**: 100% of the scaffold's automated tests pass and static analysis reports zero errors or warnings on a clean checkout.
- **SC-004**: The test suite includes at least one passing test for the public API and at least one passing test per architectural layer seam (minimum three seams).
- **SC-005**: An attempt to import a layer in violation of the inward-dependency rule (e.g., domain importing UI) is detected by the project's automated checks rather than passing silently.
- **SC-006**: Switching the shadcn theme in the playground app visibly changes the placeholder component's appearance, confirming the theming pipeline is wired end to end.
- **SC-007**: The library's public API consists only of intentionally exported symbols; no internal symbol is reachable through the public entry point.

## Assumptions

- This is the first iteration of a larger reporting/report-designer library (jet-print); placeholder content is explicitly acceptable, and the goal is a clean, extensible foundation rather than feature-complete behavior.
- "shadcn UI library" refers to the community `shadcn_ui` Flutter package; it will be integrated as the theming/component foundation for the playground app and made available to the library.
- The repository is organized as a Dart pub workspace containing the library package and the playground app as separate sibling packages sharing one lockfile, so the playground app depends on the library the same way an external consumer would.
- The playground app's primary target platform for this iteration is macOS desktop (chosen for fast native iteration); other platforms may be enabled in a later iteration.
- The architectural layers and naming follow the project constitution (domain/report model, rendering/layout, designer/UI, data binding), with data binding deferrable to a later iteration.
- "Clean and maintainable from day one" is interpreted as: enforced library/consumer separation, established layer seams with inward dependencies, a passing test harness, static analysis, and contributor documentation — consistent with the project constitution.
- Publishing to a package registry is out of scope for this iteration; the scaffold only needs to be locally consumable and structured for future publication.
