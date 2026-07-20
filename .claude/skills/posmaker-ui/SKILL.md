---
name: posmaker-ui
description: POSMaker's UI design system and hard-won layout/mobile gotchas. Load before styling or laying out anything in cashier-*.html, dashboard-*.html, customize-*.html, or manager.html — new components, buttons, modals, panels, scrollable lists, or anything touching height/viewport units.
---

# POSMaker UI conventions

POSMaker is a static HTML/CSS/JS POS SaaS: 24 business-type clones of `cashier-*.html` + `dashboard-*.html` + `customize-*.html`, plus shared `manager.html` and `dev-support.html`. No build step, no framework — plain CSS custom properties and inline styles. Every UI change to a shared pattern needs to roll out identically across the 24 clones (see the rollout workflow at the bottom).

## Color tokens (CSS custom properties, theme-aware)

Dark theme (default) and light theme both define the same token names — always style through the token, never hardcode a hex that only makes sense in one theme.

```
--accent   (brand/action color — cyan #00b4d8 by default, but store owners can
            customize this via Customize POS, so never assume a specific hex)
--bg       (page background)
--s1       (card/panel background)
--s2       (secondary surface — button backgrounds, nested cards)
--border   (hairline borders)
--text     (primary text)
--muted    (secondary/label text)
--dim      (tertiary/disabled text)
--danger-bg / --danger-text   (red — errors, void, out-of-stock)
--warn-bg   / --warn-text     (amber — low stock, pending states)
--ok-bg     / --ok-text       (green — success, in-stock, given)
```

Semantic status colors (amber/red/green) are separate from `--accent` — don't reuse the brand accent for warning/danger/success states, and don't hardcode a fixed hex for anything that should react to the owner's custom accent color.

## Component patterns

**Buttons (dashboard):** `.btn` base + `.btn-accent` (filled, active/primary) or `.btn-ghost` (bordered neutral, inactive/secondary) + `.btn-sm` for compact. Toggle groups (period filters, scope selectors) swap `btn-accent`/`btn-ghost` via `classList.toggle`, not inline style swaps.

**Buttons (cashier POS header icons):** `.choc-btn` — flex-column icon-over-label, `border-radius:14px`, `box-shadow:0 3px 8px rgba(0,0,0,.35),inset 0 1px 0 rgba(255,255,255,.25)`, hover `translateY(-3px)` + `brightness(1.12)`, active `translateY(0)` + `brightness(.9)`. Each button gets its own distinct saturated background color (never reuse a color already assigned to another header button) — logout is always red, everything else picks a fresh hue.

**Cards/panels:** `.tbl-wrap` / `.info-card` — `background:var(--s1)`, `border:1px solid var(--border)`, `border-radius:12–14px`.

**Modals:** `.mbox` — `background:var(--s1)`, `border-radius:14–20px`, `padding:20px`, `max-height:90dvh` (see the dvh gotcha below), scrollable interior.

**Toggle/filter pills:** small `btn-sm` row, one active (`btn-accent`) at a time, rest `btn-ghost`. Used for Discount scope, Best Sellers period, etc. — reuse this exact pattern for any new "pick one of N views" control rather than inventing a new one.

## Critical gotchas (all found the hard way this session — read before touching layout)

1. **Flexbox scroll trap.** Any `flex:1; overflow-y:auto` element **must** also have `min-height:0`. Without it, a flex child refuses to shrink below its content's natural size, so instead of scrolling, the overflow just gets silently clipped by a parent's `overflow:hidden`. This bites product lists, cart lists, and any scrollable panel inside a flex column — and won't show up in testing until there's enough content to actually need to shrink.

2. **`dvh` isn't safe alone.** Some Android WebView versions don't support the `dvh` unit at all — the whole declaration gets dropped, un-bounding `body`'s height and breaking every nested scroll container app-wide. Always declare a `100vh` fallback *before* `100dvh` on the same property (cascades correctly either way), and for anything load-bearing (like `body` height), back it with a JS measurement: `document.body.style.height = window.innerHeight + 'px'` on load + resize.

3. **Floating/popover panels must reposition after they resize.** A panel positioned once on open (measuring its own `offsetHeight`) goes stale if its content later grows (e.g. an item picker expanding under a toggle). Re-call the positioning function after any content change that can alter the panel's height, not just once at open time — otherwise it can drift off-screen on a shorter viewport (tablets especially).

4. **CSS Grid over nested flex rows for aligned button pads.** A calculator/numpad-style grid needs every row to divide the same number of column-units, or rows won't align. Use `display:grid;grid-template-columns:repeat(N,1fr)` with `grid-column:span`/`grid-row:span` for wide/tall keys (like a calculator's `0` or `=`), not manually-flexed sub-rows — much harder to accidentally misalign.

5. **Straight quotes only.** Curly/smart quotes (`”` `'`) inside an HTML attribute value silently break parsing — the browser treats the rest of the tag as garbage. Always verify quotes are straight ASCII (`"` `'`) after any edit, especially ones that passed through a rich-text source.

6. **Don't trust terminal/tool rendering of `/` vs `\`, or corrupted CJK/emoji bytes.** Grep and Bash output have both misrendered a literal `/` as `\` in this codebase — always double-check a suspicious character via the Read tool (which shows raw file bytes) before "fixing" something that isn't actually broken.

## Rollout workflow (applies to any UI change, not just this skill's topics)

1. Build and verify the change in `cashier-bigasan.html` / `dashboard-bigasan.html` first (the reference file).
2. Before rolling out to the other 23 clones, grep-check the exact anchor text is byte-identical across all of them — some business types (electronics, service-biz types with tips/tables, retail vs restaurant layouts) have diverged structurally in specific areas. Don't assume uniformity.
3. Write a small dry-run-then-apply Node script to scratchpad, run with `--dry` first, confirm N/N OK, then apply for real.
4. After applying, re-run the validation triad on every touched file: `new Function()` syntax check per `<script>` block, `<div>`/`<button>` open/close balance count, and confirm the new marker string is present the expected number of times.
5. If it's a `cashier-*.html` change, bump `version.json` (new changelog entry, newest first) and `POS_BUILD` across all 24 cashier files together — that's what triggers the in-app Update Now prompt. Dashboard-only or customize-only changes don't need a `POS_BUILD` bump.
