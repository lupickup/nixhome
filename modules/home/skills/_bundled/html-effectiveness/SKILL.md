---
name: html-effectiveness
description: Reach for HTML pages instead of Markdown when the response would benefit from real typography, layout, color, SVG, charts, or interactive controls — long structured documents, side-by-side comparisons, multi-section reports, design specs, code reviews, status reports, dashboards, or any back-and-forth where Markdown feels cramped. Use proactively when about to produce a long Markdown wall, an ASCII-art diagram, or a complex text table (4+ rows or 3+ columns); render the answer as a self-contained HTML file the user can open in a browser. The references/gallery/ directory contains 20 worked examples spanning specs, code review, design, prototypes, reports, research, and custom editors — read the closest match before writing.
license: MIT AND Apache-2.0
---

# HTML Effectiveness

## Core thesis

Markdown is enough for short replies and source-of-truth docs. **HTML wins when the conversation needs presentation** — when the user will get more out of layout, color, diagrams, or controls they can manipulate than they will from a wall of text. When in doubt, ask: *"would the reader rather scroll this in chat or open a tab?"* If it's the second, write HTML.

## When HTML is the right medium

- **Long structured documents** painful to read top-to-bottom in chat (specs, plans, comparisons, audits, research synthesis).
- **Visual reasoning** — diffs with margin annotations, before/after architecture, flow charts, dashboards, status surfaces.
- **Side-by-side comparisons** that Markdown tables can't render readably (>4 rows or >3 columns).
- **Interactive elements** — sliders, toggles, prompt tuners, prototype previews where the user "tweaks to see what happens".
- **Anything the user will share or come back to** — links beat scrolled chat history.

## When NOT to use HTML

- **Short, direct questions.** A two-sentence answer doesn't need a tab.
- **Source-of-truth docs that other tooling consumes.** READMEs, ADRs, runbooks stay Markdown — those are read by people *and* tools.
- **When generation cost outweighs the win.** HTML takes 2-4× longer to write and produces noisier diffs. Pick it when presentation actually pays back.

## Relationship to visual-explainer

This skill is about **medium choice**, not specific recipes. If a use case maps to a `visual-explainer` slash command (`/visual-explainer:diff-review`, `/plan-review`, `/project-recap`, `/generate-slides`, `/generate-web-diagram`, `/generate-visual-plan`, `/fact-check`, `/share-page`), use that — it's a tighter, opinionated path. This skill covers everything else: the long tail of "this would be better as a webpage" moments visual-explainer doesn't have a command for.

## How to do it well

1. **Pick a pattern from `references/gallery/`** that matches the use case. See `references/gallery/INDEX.md` for the taxonomy. Don't start from a blank file.
2. **Self-contained — no build step.** Inline CSS, system-stack fonts, SVG inline. The user opens the file directly in a browser; no network requests at runtime.
3. **Output to `~/.agent/diagrams/<short-descriptive-name>.html`** — shared with the visual-explainer skill so both surface in the user's HTTP server / browse history.
4. **Tell the user the file path** and a one-line summary. Don't dump HTML into chat.
5. **Light/dark theme aware** when feasible. Resilient typography (`system-ui` stack). No external network requests at runtime.

## The 20-pattern gallery

`references/gallery/` bundles examples from Thariq Shihipar's `ThariqS/html-effectiveness` repository. Five clusters:

- **Specs & exploration** — code-approach comparisons, visual designs, implementation plans, PR writeups
- **Code review** — annotated diffs, code-understanding walkthroughs
- **Design & prototypes** — design systems, component variants, animation/interaction prototypes, slide decks, SVG illustrations
- **Reports & research** — status reports, incident reports, flowcharts, feature/concept explainers
- **Custom editors** — triage boards, feature-flag editors, prompt tuners with copy-as export

`references/gallery/INDEX.md` lists every example with a one-liner and which cluster it belongs to. Read the gallery file closest to your task before generating. Borrow structure liberally; don't slavishly clone.

## Credit

Patterns and thesis from Thariq Shihipar's *"The unreasonable effectiveness of HTML"*: <https://github.com/ThariqS/html-effectiveness>. The bundled gallery examples are redistributed under Apache-2.0; see `references/gallery/LICENSE`.
