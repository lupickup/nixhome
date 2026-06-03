# Gallery index

Twenty worked HTML examples grouped by use-case cluster. Each filename in this directory is a self-contained HTML page — open it in a browser to see how a pattern is realised, then adapt the layout/CSS for your own output.

The bundled files are sourced from `ThariqS/html-effectiveness` and redistributed under Apache-2.0; see `LICENSE` in this directory.

## Specs & exploration

- **`01-exploration-code-approaches.html`** — side-by-side comparison of multiple implementation approaches; trade-off matrix with rationale per option.
- **`02-exploration-visual-designs.html`** — exploring multiple visual designs side-by-side before committing.
- **`16-implementation-plan.html`** — phased implementation plan with milestones, work breakdown, and dependencies.
- **`17-pr-writeup.html`** — pre-submit PR writeup: motivation, approach, risk surface, test plan.

## Code review

- **`03-code-review-pr.html`** — diff review with inline margin annotations, severity-coloured findings, and summary verdict.
- **`04-code-understanding.html`** — walkthrough explaining how a piece of code works; structure for onboarding/refresh.

## Design & prototypes

- **`05-design-system.html`** — the design system reference page (palette, typography, components) for consistent styling across other generated pages.
- **`06-component-variants.html`** — gallery of a single component in its variants/states.
- **`07-prototype-animation.html`** — animation prototype using CSS keyframes / JS timelines.
- **`08-prototype-interaction.html`** — interactive prototype with controls (sliders, knobs, toggles) for the user to manipulate.
- **`09-slide-deck.html`** — magazine-quality slide deck pattern with section transitions and presenter framing.
- **`10-svg-illustrations.html`** — inline SVG illustrations for concept explanation.

## Reports & research

- **`11-status-report.html`** — periodic status report with KPIs, narrative, and next-period focus.
- **`12-incident-report.html`** — post-incident writeup: timeline, root cause, mitigations, follow-ups.
- **`13-flowchart-diagram.html`** — flowchart / process diagram pattern.
- **`14-research-feature-explainer.html`** — feature explainer for a researched topic (concrete, narrow scope).
- **`15-research-concept-explainer.html`** — concept explainer (broader, foundational).

## Custom editing interfaces

- **`18-editor-triage-board.html`** — purpose-built editor for triaging a backlog (drag/reorder, status changes).
- **`19-editor-feature-flags.html`** — feature-flag editor with copy-as-config export.
- **`20-editor-prompt-tuner.html`** — interactive prompt-tuning surface with copy-as export.

## Design system reference

`05-design-system.html` is the *reference page* for the gallery's visual language. When generating a new HTML page, sample its palette / type scale / spacing for visual consistency unless the situation explicitly calls for a different look (e.g. a project's existing design tokens).

## Index page

`index.html` is the masthead that links the entire gallery — reproduce locally if you want a one-page entry to all 20 patterns.
