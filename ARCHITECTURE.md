# nodepad — Features & Architecture

> by Saleh Kayyali · [mskayyali.com](http://mskayyali.com)

This document describes what nodepad does, why it works the way it does, and how each feature maps to the code that powers it. Features are described first; architecture is explained in the context of those features.

---

## Part I — Features

### 1. Spatial Canvas (Tiling View)

The default view places every note as a tile on a spatial grid. The layout engine is a **Binary Space Partitioning (BSP) tree** — the canvas is recursively split, alternating vertical and horizontal cuts, with each split producing two siblings that share the available space proportionally.

Notes are chunked into **pages of 7**. Pages scroll horizontally, making the canvas feel infinite without losing spatial orientation. A **minimap** in the bottom-right corner shows a proportional thumbnail of all pages and highlights the current one, appearing as soon as more than one page exists.

**What this gives the user**: an always-visible, scannable overview of all their thinking — not a list, a space.

### 2. Kanban View

An alternative layout that groups notes into columns by content type. Column order prioritises tasks and thesis notes first, then everything else alphabetically. A floating **column minimap** shows type icons with live count badges so users can jump to any column without scrolling.

**When to use it**: reviewing thinking by category, managing tasks, or seeing the overall distribution of note types.

### 3. Graph View

A third view (⌘3) that renders all notes as an interactive force-directed graph using **D3.js**. The layout is driven by real AI-detected connections (`influencedBy`) — no artificial spoke lines or center anchors. A **centrality-radial force** (`d3.forceRadial`) positions highly-connected notes near the center and isolated notes at the periphery, so the layout itself encodes the importance of each note in the research network.

The synthesis note (if present) has the highest connection degree and naturally settles near the center.

**Simulation design**: two effects manage the lifecycle — an init-once effect creates the simulation and stops it; an update effect mutates nodes and links in-place and reheats with a controlled alpha (`0.4` for new nodes, `0.15` for enrichment completion). This prevents the violent restarts that would occur if the simulation were recreated on every render.

**Enriching nodes** are fixed at their current position (`fx/fy`) during enrichment so they don't drift; the fix is released when enrichment completes and the simulation gently reheats.

**Interaction**: click a node to open a full detail panel (30% of canvas width) showing the same fields as a tile card — editable text, editable annotation, editable category, confidence bar, sources, and a connected-nodes list. Hover a node to dim the unrelated graph. The canvas index (⌘I) also drives graph highlighting — hovering a title in the index highlights the corresponding node.

**Selection & dimming**: `focalId = hoveredId ?? selectedId ?? highlightedBlockId`. Selecting a node keeps its connections lit even after the cursor moves away. Clicking the SVG background deselects (a `didPan` ref prevents pan gestures from accidentally deselecting). `Escape` clears selection from anywhere. Simulation is only kicked (`alphaTarget(0.3)`) on actual drag movement, not on mousedown, so clicking a node doesn't jolt the graph.

**What this gives the user**: a spatial perspective focused entirely on relationships, making it easy to see which notes are hubs and which are isolated observations.

### 3. AI Enrichment — Automatic Classification

Every note is automatically classified into one of **14 content types** the moment it is created or edited. Classification happens in two passes:

1. **Heuristic pass** (instant, client-side): regex patterns classify the note locally before the API call. Quote delimiters, URLs, question marks, word count, and task keywords give a fast initial type.
2. **AI pass** (async, server-side): the note is sent to the AI together with context from the rest of the canvas. The AI returns a final `contentType`, a `category` label (topic cluster), a 2–4 sentence `annotation`, an `influencedBy` list of related block IDs, a `confidence` score for claims, and optionally a `mergeWithIndex` pointing to a block the new note should merge into.

The 14 types are: `claim`, `question`, `idea`, `task`, `thesis`, `quote`, `entity`, `reference`, `definition`, `opinion`, `reflection`, `narrative`, `comparison`, `general`. Each has its own accent colour (oklch), icon, and rendering style.

**Shorthand override**: typing `#claim This is a claim` or `#question What about X?` at the start of a note forces that type, bypassing the AI classification.

### 4. Contextual Annotation

Every note receives a 2–4 sentence AI-written annotation that explains the note **in the context of everything else on the canvas** — not in isolation. The annotation is shown below the note body in the tile. Users can edit it inline by clicking the text.

This is the core of nodepad's value proposition: the same sentence means different things in different research contexts. The annotation captures that meaning.

### 5. Connection Mapping

The AI returns `influencedByIndices` for every enriched note, pointing to semantically related notes on the canvas. These are stored as stable block IDs in `influencedBy`.

In both tiling and kanban views, a **three-dot indicator** appears in the header of any note that has connections. Hovering the dots dims all unrelated tiles (`opacity-15 saturate-0`) and leaves the connected cluster highlighted, making the relationship immediately visible.

### 6. Confidence Scoring

For `claim`-type notes, the AI returns a `confidence` score (0–100). A thin bar is shown at the bottom of the tile and in the markdown export as a table column. This helps users track which claims are well-supported versus speculative.

### 7. Web Grounding (Live Sources)

When web grounding is enabled in settings and the selected model supports it (`:online` suffix via OpenRouter), truth-dependent note types — `claim`, `question`, `entity`, `quote`, `reference`, `definition`, `narrative` — are verified against live web sources. Citations come back as `sources[]` with URL, title, and site name, and are rendered as linked references in the tile.

### 8. Synthesis (Ghost Notes)

After a threshold is reached (≥3 blocks, ≥3 new blocks since last synthesis, ≥2 minutes elapsed), nodepad silently calls `/api/ghost` and generates a **15–25 word emergent thesis** drawn from the whole canvas. This is not a summary — it's an attempt to name the underlying idea the user is circling.

The synthesis appears in a slide-in **Synthesis panel** (right side, sparkle icon in the status bar). A badge on the icon shows when a new synthesis is ready. Users can:
- **Solidify** — converts the synthesis into a `thesis` tile on the canvas
- **Dismiss** — clears it

Past synthesis notes accumulate in the panel as a history. Near-duplicate detection prevents the same thesis from appearing twice (the last 10 syntheses are sent as context).

### 9. Task Management

Notes classified as `task` behave differently from all other types:
- They are excluded from the BSP tiling grid and rendered in a dedicated task strip above the canvas.
- New notes classified as tasks are appended as **sub-tasks** inside an existing task tile rather than creating a new tile.
- Sub-tasks have individual checkboxes and can be added, completed, and deleted inline.

### 10. Projects

All notes belong to a **project** (research space). Multiple projects can exist simultaneously. The sidebar (left panel) lists all projects with rename and delete actions. Switching projects is instant — all state is in memory and localStorage.

New projects start empty. The active project is persisted across sessions.

### 11. Export

Three export formats, all accessible from the `⌘K` command menu:

| Format | Description |
|---|---|
| **Export .nodepad** | Full-fidelity JSON file. Re-importable on any device. Strips transient UI state. |
| **Import .nodepad** | Loads a `.nodepad` file as a new project (never overwrites existing). Name conflicts get a `(2)`, `(3)` suffix. |
| **Export Markdown** | Richly formatted `.md` file with YAML front matter, stats table, TOC with anchor links, claims as confidence tables, tasks as GFM checklists, quotes as blockquotes, annotations as blockquotes, cited sources as lists. |
| **Copy Markdown** | Same as Export Markdown but copies to clipboard. |

### 12. Undo

`⌘Z` undoes the last canvas mutation. A ring of up to 20 snapshots is kept per project in memory. A brief toast confirms the undo. History is not persisted — it resets on page reload.

### 13. Persistence & Backup

All data lives in the user's browser localStorage:
- **Primary store**: `nodepad-projects` — written on every state change
- **Silent backup**: `nodepad-backup` — a rolling copy written in parallel. If the primary store is ever missing on load (e.g. storage cleared), the backup is restored automatically with a console notice.
- **AI settings**: `nodepad-ai-settings` — API key, model choice, web grounding toggle

No data is sent to any server except note text forwarded to OpenRouter for enrichment, using the user's own API key.

### 14. RTL Support

Arabic and Hebrew text is detected automatically and the `.rtl-text` CSS class is applied to the tile body, switching text direction and alignment.

### 15. About Panel

A `?` button in the top-right of the status bar opens a full-height sliding panel with a structured guide to the app: the idea, quick start steps, content types, views, AI features, export/data, keyboard shortcuts, and usage tips.

### 16. Feature Parity Across Views

All three views render the same `TileCard` component (tiling, kanban) or an equivalent `GraphDetailPanel` (graph). Features available in every view:

- Edit note text (double-click)
- Edit annotation (double-click)
- Edit category (click the category badge — triggers re-enrichment with the new category as a hint)
- Delete note
- Re-enrich note
- Confidence bar (claims)
- Sources with clickable links (web grounding)
- Connected nodes list

**Tiling-only**: pinning (`isPinned`). The pin gradient and visual treatment are a spatial feature of the tiling layout and are not surfaced in kanban or graph views.

### 17. Clickable Links in Annotations

AI annotations are written in Markdown and can contain inline links (e.g. `[Source](https://...)`). All annotation rendering passes through `react-markdown` + `remark-gfm` so these links are rendered as proper `<a>` tags that open in a new tab. This applies to tile cards in tiling and kanban views, and to the graph detail panel.

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘K` | Open command menu |
| `⌘Z` | Undo |
| `⌘1` | Tiling view |
| `⌘2` | Kanban view |
| `⌘3` | Graph view |
| `⌘P` | Toggle projects sidebar |
| `⌘I` | Toggle canvas index |
| `⌘G` | Toggle synthesis panel |
| `Enter` | Submit a new note |
| `Esc` | Close command menu / deselect graph node |

---

## Part II — Technical Architecture

### Stack

| Layer | Technology |
|---|---|
| Framework | Next.js 16.1.6, App Router |
| UI | React 19, TypeScript 5.7, `"use client"` throughout |
| Styling | Tailwind CSS v4, oklch colour space, CSS variables for type colours |
| Components | `sheet.tsx` only — one shadcn/ui primitive (Radix Sheet). All other shadcn scaffolding removed. |
| Animations | Framer Motion 11 |
| Icons | Lucide React |
| Graph | D3.js (`d3-force`, `d3-zoom`) — Graph View simulation |
| Command palette | `cmdk` 1.1 |
| Markdown render | `react-markdown` + `remark-gfm` |
| AI API | OpenRouter (user's own key, forwarded via `x-or-key` header) |
| Analytics | `@vercel/analytics` |
| Fonts | Geist + Geist Mono, Vazirmatn (RTL, via `next/font/google` → `--font-vazirmatn` CSS variable) |

### State Architecture

All state lives in `app/page.tsx`, which is the single root component. There is no global state library (no Redux, no Zustand). State flows down via props; mutations flow up via callbacks.

```
app/page.tsx  ←  owns everything
  ├── StatusBar
  ├── ProjectSidebar
  ├── TilingArea / KanbanArea / GraphArea   ← receives blocks + callbacks
  │     └── TileCard (×N)                  ← receives one block + callbacks
  │     └── GraphDetailPanel               ← graph-only side panel
  ├── TileIndex
  ├── GhostPanel
  ├── VimInput                             ← addBlock() lives here
  └── AboutPanel
```

Key state in `page.tsx`:

```typescript
projects: Project[]                    // persisted → localStorage: nodepad-projects
activeProjectId: string                // persisted → localStorage: nodepad-active-project
viewMode: "tiling"|"kanban"|"graph"    // ephemeral
highlightedBlockId: string             // ephemeral, cross-panel hover sync (all views incl. graph)
isSidebarOpen: boolean                 // ephemeral
isIndexOpen: boolean                   // ephemeral
isGhostPanelOpen: boolean              // ephemeral
isCommandKOpen: boolean                // ephemeral
```

### Feature → Code Map

#### Spatial canvas (BSP tiling)
**`components/tiling-area.tsx`**
- `buildBSPTree(blocks)` — recursively splits block arrays into a binary tree, alternating `"vertical"` / `"horizontal"` splits
- `PAGE_SIZE = 7` — task blocks are filtered out before paging
- `TileRenderer` — renders a BSP node; leaf nodes render a `TileCard`, branch nodes render two children with a flexbox split
- Pages container uses auto height (not `h-full`) so pages stack naturally and the scroll container grows with content
- `TilingMinimap` positioned `absolute bottom-4 right-4`, visible when `pages.length > 1`

#### Connection dimming
**`components/tiling-area.tsx`** and **`components/kanban-area.tsx`**
- `hoveredConnectionId: string | null` — which block's dots are being hovered
- `relatedIds: Set<string>` — useMemo over `blocks` that finds every block connected to `hoveredConnectionId` via `influencedBy` (bidirectional)
- Wrapper div on each tile: `opacity-15 saturate-0` when the tile is neither the hovered block nor in `relatedIds`

#### AI enrichment
**`app/api/enrich/route.ts`**
- Heuristic pre-classification runs first (no API call needed for clear cases)
- Context passed as XML: `<note index="N" category="X">text</note>` — limits prompt injection blast radius to wrong classification only
- OpenRouter called with `json_schema` + `strict: true` structured output
- `:online` suffix appended automatically for truth-dependent types when `x-or-supports-grounding: true`
- **Language isolation**: `detectScript(text)` detects script via Unicode ranges (Arabic, Hebrew, CJK, Cyrillic, Devanagari; Latin-script deferred to model). Injects `[RESPOND IN: X]` directive directly before `<note_to_enrich>` so context notes in a different language cannot bleed into the response language.

In `app/page.tsx`:
- `enrichBlock(id, text, forcedType?)` — fires after `addBlock()` and after debounced edits (800ms)
- `mergeWithIndex` response → merge new block text into existing block instead of creating a tile
- `"task"` type response → append as sub-task to existing task block

#### Synthesis
**`app/api/ghost/route.ts`**
- Receives `context` (all blocks) + `previousSyntheses` (last 10) in the prompt
- Instructs recency weighting and near-duplicate avoidance
- Falls back to `gemini-2.0-flash-lite` if no model header

In `app/page.tsx`:
- `generateGhostNote()` — checks ≥3 blocks, cooldown (≥2 min), block count delta (≥3 new), no active ghost
- `solidifyGhost()` — creates a `thesis` block and clears the ghost

**`components/ghost-panel.tsx`**
- Slide-in right panel showing generating state, current ghost, solidify/dismiss actions, history list

#### Export
**`lib/export.ts`** — `exportToMarkdown()` builds sections in research-logical order: thesis → claims (confidence table) → questions → ideas → tasks (GFM checklist) → quotes (blockquotes) → entities, definitions, references → opinions, reflections, narratives, comparisons → general. YAML front matter includes project name, date, node count, model. TOC with anchor links. Attribution footer: `nodepad — https://nodepad.space`.

**`lib/nodepad-format.ts`** — `.nodepad` file: JSON with `{ version: 1, exportedAt, project: { ... } }`. `serialiseProject()` strips `isEnriching`, `isError`, `statusText`. `parseNodepadFile()` validates structure, assigns a fresh UUID, resolves name collisions.

#### Undo
`blockHistoryRef: Record<projectId, TextBlock[][]>` — up to 20 snapshots per project, stored in a `useRef` (not state, so mutations don't trigger re-renders). `pushHistory()` is called before every mutation. `undo()` pops the stack and calls `updateActiveProject` with the restored blocks.

#### Persistence & backup
Two `useEffect`s in `page.tsx`:
1. Load effect — reads `nodepad-projects`; falls back to `nodepad-backup` if absent; falls back further to legacy `nodepad-blocks` key (migration); seeds from `INITIAL_PROJECTS` if nothing found.
2. Save effect — writes `nodepad-projects` + `nodepad-active-project` + `nodepad-backup` on every `projects` / `activeProjectId` change.

#### Security
**`proxy.ts`** (Next.js proxy, applied to `/api/enrich` and `/api/ghost`):
- Sliding-window in-memory rate limiter: `Map<ip, { timestamps: number[] }>` — 60 req/min enrich, 10 req/min ghost
- Origin header check: rejects cross-origin requests (localhost bypassed)
- Strips `x-or-key` from response headers

Works reliably on Render.com (persistent process). On Vercel (serverless), the in-memory map can reset between cold starts — rate limiting is best-effort only.

#### Content type system
**`lib/content-types.ts`** — `CONTENT_TYPE_CONFIG` maps each of the 14 types to `{ label, icon, accentVar, bodyStyle? }`. `accentVar` is a CSS custom property (`--type-claim`, etc.) defined in `app/globals.css` as oklch values. `thesis` uses a gradient variable.

**`lib/detect-content-type.ts`** — pure function, no API call. Pattern order matters: quote → task → question → definition → comparison → URL → idea → reflection → opinion → entity (≤3 words) → claim (4–25 words) → narrative (>25 words) → general.

### Data Flow — Adding a Note

```
User types in VimInput → presses Enter
  ↓
addBlock(text)                          [page.tsx]
  ↓
detectContentType(text)                 [lib/detect-content-type.ts]  ← instant heuristic
  ↓
setProjects(...)                        ← tile appears on canvas immediately
  ↓
pushHistory(projectId, blocks)          ← snapshot saved for undo
  ↓
enrichBlock(newBlock.id, text)          [page.tsx]
  ↓
POST /api/enrich { text, context[-15 blocks], forcedType? }
  ↓
  ├── heuristic re-check
  └── OpenRouter (json_schema strict)
        ↓
  { contentType, category, annotation, confidence,
    influencedByIndices, isUnrelated, mergeWithIndex }
  ↓
updateActiveProject(...)                ← tile updates with AI results
  ↓
generateGhostNote()?                    ← maybe trigger synthesis
```

### Data Flow — Synthesis

```
enrichBlock() completes
  ↓
generateGhostNote() checks:
  - blocks.length ≥ 3
  - no ghost currently generating
  - (blocks.length - lastGhostBlockCount) ≥ 3
  - (now - lastGhostTimestamp) ≥ 120_000ms
  ↓
POST /api/ghost { context, previousSyntheses[-10] }
  ↓
{ text, category }
  ↓
setProjects(...ghostNote: { text, isGenerating: false })
  ↓
GhostPanel shows new synthesis + badge on status bar icon
  ↓
User: Solidify → creates thesis block + clears ghost
User: Dismiss → clears ghost, sets ghostNoteDismissed
```

### File Map

```
app/
  page.tsx                  State hub, all callbacks
  layout.tsx                Fonts, metadata, Analytics
  globals.css               CSS variables, type colours, animations
  api/
    enrich/route.ts         AI enrichment endpoint
    ghost/route.ts          Synthesis endpoint

components/
  tile-card.tsx             Block tile (core UI unit), TextBlock type export
  tiling-area.tsx           BSP tiling layout + connection dimming
  tiling-minimap.tsx        Spatial minimap (bottom-right, tiling view)
  kanban-area.tsx           Column layout + connection dimming
  kanban-minimap.tsx        Column jump minimap (kanban view)
  graph-area.tsx            D3 force-directed graph view (SVG + React)
  graph-detail-panel.tsx    Graph side panel: full block detail + editing
  project-sidebar.tsx       Left panel: projects list + AI settings
  ghost-panel.tsx           Right panel: synthesis notes
  tile-index.tsx            Right panel: canvas index by category/type
  status-bar.tsx            Top bar: all status indicators + panel toggles
  vim-input.tsx             Bottom input + ⌘K command grid (Views/Nav/Actions)
  about-panel.tsx           Full-height right Sheet: app guide
  ui/
    sheet.tsx               Only remaining shadcn/ui primitive (Radix Sheet, used by about-panel)

lib/
  content-types.ts          14 ContentType definitions + CONTENT_TYPE_CONFIG
  detect-content-type.ts    Heuristic pre-classifier (no API)
  ai-settings.ts            useAISettings hook, getAIHeaders, model list
  export.ts                 Markdown export (rich format)
  nodepad-format.ts         .nodepad file serialise/parse
  initial-data.ts           INITIAL_PROJECTS seed
  utils.ts                  cn() utility

proxy.ts                    Rate limiting + origin check + header stripping
```
