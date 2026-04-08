# Nodepad CLI Conversion Analysis

A comprehensive analysis of strategies for building a CLI/TUI version of Nodepad that could share logic with the existing web application.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [CLI Framework Comparison](#cli-framework-comparison)
4. [Component Reuse Strategy](#component-reuse-strategy)
5. [Data Layer Migration](#data-layer-migration)
6. [Spatial Canvas in Terminal](#spatial-canvas-in-terminal)
7. [AI Integration Patterns](#ai-integration-patterns)
8. [Recommended Architecture](#recommended-architecture)
9. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

### Recommendation: Ink + Shared Core Library

After analyzing Nodepad's architecture and researching CLI frameworks, the recommended approach is:

1. **Use Ink** (React for CLI) as the TUI framework - enables maximum React knowledge transfer
2. **Extract a headless `@nodepad/core`** package with pure business logic
3. **Use SQLite** (via better-sqlite3) for CLI storage with JSON export compatibility
4. **Implement simplified views**: List, Tree, and ASCII Graph for spatial representation
5. **Stream AI responses** directly to terminal with ora spinners for feedback

**Estimated effort**: 4-6 weeks for MVP with feature parity on core note-taking

---

## Current Architecture Analysis

### Tech Stack
- **Framework**: Next.js 16, React 19, TypeScript
- **UI**: Tailwind CSS, Framer Motion, Radix UI
- **Visualization**: D3.js for force-directed graph
- **Storage**: localStorage with JSON backup/restore
- **AI**: Multi-provider support (OpenRouter, OpenAI, Z.ai)

### Core Data Model

```typescript
// lib/content-types.ts - 14 content types
type ContentType = 
  | 'entity' | 'claim' | 'question' | 'task' | 'idea'
  | 'reference' | 'quote' | 'note' | 'summary' | 'definition'
  | 'example' | 'counterpoint' | 'connection' | 'meta';

// TextBlock - the fundamental unit
interface TextBlock {
  id: string;
  text: string;
  timestamp: number;
  contentType: ContentType;
  category: string;
  annotation: string;
  confidence: number;
  sources: string[];
  influencedBy: string[];  // Connection graph edges
  isPinned: boolean;
  subTasks?: SubTask[];
}

// Project - container for blocks
interface Project {
  id: string;
  name: string;
  blocks: TextBlock[];
  collapsedIds: string[];
  ghostNotes: GhostNote[];
  lastGhostBlockCount: number;
  lastGhostTimestamp: number;
  lastGhostTexts: string[];
}
```

### Key Features to Port
1. **Note CRUD** - Create, read, update, delete blocks
2. **Content Classification** - AI-powered type detection
3. **Connection Detection** - `influencedBy` relationship inference
4. **Ghost Notes** - AI synthesis across categories
5. **Multiple Views** - Tiling, Kanban, Graph
6. **Search/Filter** - By type, category, text
7. **Import/Export** - `.nodepad` JSON format

---

## CLI Framework Comparison

### Framework Matrix

| Feature | Ink | Blessed | Oclif | Inquirer |
|---------|-----|---------|-------|----------|
| **Stars** | 37.4k | 11.8k | 9.5k | 21k |
| **React-based** | Yes | No | No | No |
| **TUI Support** | Flexbox | Curses | Command-only | Prompts-only |
| **Component Model** | JSX | Widgets | Commands | Questions |
| **Maintenance** | Active | Stale | Active | Active |
| **TypeScript** | Excellent | Poor | Excellent | Good |
| **Learning Curve** | Low (React devs) | High | Medium | Low |

### Detailed Analysis

#### Ink (Recommended)
**Pros:**
- React renderer for CLI using Yoga (Flexbox)
- Direct React knowledge transfer from web codebase
- Powers production CLIs: Claude Code, Gemini CLI, Prisma, Cloudflare Wrangler
- Hooks work (`useState`, `useEffect`, `useContext`)
- Active maintenance, excellent TypeScript support
- Components: `<Box>`, `<Text>`, `<TextInput>`, `<Spinner>`

**Cons:**
- No complex widgets (tables, trees built-in)
- Limited to stdout/stderr (no ncurses-style screen control)
- Requires `ink-*` ecosystem for advanced features

**Example:**
```tsx
import { render, Box, Text, useInput } from 'ink';
import { useState } from 'react';

function NoteList({ blocks }: { blocks: TextBlock[] }) {
  const [selected, setSelected] = useState(0);
  
  useInput((input, key) => {
    if (key.upArrow) setSelected(s => Math.max(0, s - 1));
    if (key.downArrow) setSelected(s => Math.min(blocks.length - 1, s + 1));
  });

  return (
    <Box flexDirection="column">
      {blocks.map((block, i) => (
        <Box key={block.id}>
          <Text color={i === selected ? 'cyan' : 'white'}>
            {i === selected ? '>' : ' '} [{block.contentType}] {block.text.slice(0, 60)}
          </Text>
        </Box>
      ))}
    </Box>
  );
}
```

#### Blessed / Blessed-contrib
**Pros:**
- Full ncurses-style TUI with mouse support
- Rich widget library: tables, trees, forms, gauges
- blessed-contrib adds: line charts, maps, sparklines, markdown
- Fine-grained screen control and damage optimization

**Cons:**
- No React integration (imperative API)
- Maintenance has stalled (last commit 2+ years)
- Would require complete UI rewrite
- Poor TypeScript support

**Best for:** Dashboard-heavy applications, maximum visual fidelity

#### Oclif
**Pros:**
- Salesforce-backed, production-grade
- Excellent command parsing, help generation
- Plugin system, auto-updates

**Cons:**
- Command-focused, not TUI-focused
- Would need to pair with Ink or Blessed for interactive UI

**Best for:** Traditional CLI tools, not interactive TUIs

### Verdict: Ink

Ink is the clear choice because:
1. React knowledge transfers directly
2. Shared mental model with web codebase
3. Active ecosystem with growing adoption
4. Sufficient for note-taking TUI requirements

---

## Component Reuse Strategy

### What Can Be Shared

| Layer | Web | CLI | Shareable? |
|-------|-----|-----|------------|
| Data Model | TypeScript interfaces | Same | **100%** |
| Business Logic | Functions in `/lib` | Same | **90%** |
| AI Integration | `ai-enrich.ts`, `ai-ghost.ts` | Same | **95%** |
| State Management | React hooks | React hooks | **80%** |
| UI Components | React + Tailwind | Ink components | **0%** (rewrite) |
| Visualization | D3.js | ASCII art | **0%** (rewrite) |
| Storage | localStorage | SQLite/JSON files | **20%** (adapter) |

### Extraction Plan: @nodepad/core

Create a shared package with platform-agnostic logic:

```
packages/
  core/                    # @nodepad/core - shared logic
    src/
      types/               # All TypeScript interfaces
        block.ts
        project.ts
        content-types.ts
      ai/                  # AI integration
        enrich.ts          # Block classification
        ghost.ts           # Ghost note synthesis
        providers.ts       # Multi-provider abstraction
      operations/          # Pure business logic
        block-ops.ts       # CRUD operations
        search.ts          # Search/filter
        connections.ts     # Graph algorithms
        import-export.ts   # .nodepad format
      storage/             # Storage abstraction
        interface.ts       # StorageAdapter interface
        memory.ts          # In-memory (testing)
  
  web/                     # Next.js app (current)
    lib/
      storage/
        local-storage.ts   # implements StorageAdapter
    
  cli/                     # Ink CLI app (new)
    src/
      storage/
        sqlite.ts          # implements StorageAdapter
        json-file.ts       # implements StorageAdapter
```

### Storage Adapter Interface

```typescript
// packages/core/src/storage/interface.ts
export interface StorageAdapter {
  // Projects
  getProjects(): Promise<Project[]>;
  getProject(id: string): Promise<Project | null>;
  saveProject(project: Project): Promise<void>;
  deleteProject(id: string): Promise<void>;
  
  // Blocks (within project context)
  getBlocks(projectId: string): Promise<TextBlock[]>;
  getBlock(projectId: string, blockId: string): Promise<TextBlock | null>;
  saveBlock(projectId: string, block: TextBlock): Promise<void>;
  deleteBlock(projectId: string, blockId: string): Promise<void>;
  
  // Search
  searchBlocks(projectId: string, query: SearchQuery): Promise<TextBlock[]>;
  
  // Sync/Export
  exportProject(projectId: string): Promise<NodepadFile>;
  importProject(file: NodepadFile): Promise<Project>;
}
```

---

## Data Layer Migration

### Storage Options Comparison

| Storage | Pros | Cons | Best For |
|---------|------|------|----------|
| **SQLite** | Fast queries, indexing, full-text search | Binary, requires native module | Primary CLI storage |
| **JSON Files** | Human-readable, git-friendly, portable | Slow for large datasets, no indexing | Backup/sync |
| **Markdown** | Universal, editable anywhere | Lossy (no metadata), complex parsing | Export only |

### Recommended: SQLite + JSON Export

Use **better-sqlite3** for primary storage with JSON export for portability:

```typescript
// packages/cli/src/storage/sqlite.ts
import Database from 'better-sqlite3';
import type { StorageAdapter, Project, TextBlock } from '@nodepad/core';

export class SQLiteStorage implements StorageAdapter {
  private db: Database.Database;
  
  constructor(dbPath: string = '~/.nodepad/nodepad.db') {
    this.db = new Database(dbPath);
    this.db.pragma('journal_mode = WAL');
    this.initSchema();
  }
  
  private initSchema() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER,
        updated_at INTEGER
      );
      
      CREATE TABLE IF NOT EXISTS blocks (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        text TEXT NOT NULL,
        content_type TEXT NOT NULL,
        category TEXT,
        annotation TEXT,
        confidence REAL DEFAULT 0.5,
        is_pinned INTEGER DEFAULT 0,
        timestamp INTEGER,
        sources TEXT,           -- JSON array
        influenced_by TEXT,     -- JSON array
        sub_tasks TEXT,         -- JSON array
        FOREIGN KEY (project_id) REFERENCES projects(id)
      );
      
      CREATE INDEX IF NOT EXISTS idx_blocks_project ON blocks(project_id);
      CREATE INDEX IF NOT EXISTS idx_blocks_type ON blocks(content_type);
      CREATE INDEX IF NOT EXISTS idx_blocks_category ON blocks(category);
      
      -- Full-text search
      CREATE VIRTUAL TABLE IF NOT EXISTS blocks_fts USING fts5(
        text, annotation, content='blocks', content_rowid='rowid'
      );
    `);
  }
  
  async searchBlocks(projectId: string, query: SearchQuery): Promise<TextBlock[]> {
    if (query.text) {
      // Use FTS for text search
      const rows = this.db.prepare(`
        SELECT b.* FROM blocks b
        JOIN blocks_fts fts ON b.rowid = fts.rowid
        WHERE b.project_id = ? AND blocks_fts MATCH ?
      `).all(projectId, query.text);
      return rows.map(this.rowToBlock);
    }
    // Regular query with filters
    // ...
  }
}
```

### Directory Structure

```
~/.nodepad/
  nodepad.db              # SQLite database
  config.json             # User settings, API keys
  exports/                # .nodepad JSON exports
  backups/                # Automatic backups
```

### Sync Strategy

```typescript
// Bidirectional sync with web version
export async function syncWithWeb(
  sqliteStorage: SQLiteStorage,
  nodepadFile: NodepadFile
): Promise<SyncResult> {
  const localProject = await sqliteStorage.getProject(nodepadFile.project.id);
  
  if (!localProject) {
    // Import from web
    await sqliteStorage.importProject(nodepadFile);
    return { action: 'imported' };
  }
  
  // Merge strategy: last-write-wins per block
  const merged = mergeProjects(localProject, nodepadFile.project);
  await sqliteStorage.saveProject(merged);
  return { action: 'merged', conflicts: merged.conflicts };
}
```

---

## Spatial Canvas in Terminal

### Challenge

The web version has three views:
1. **Tiling** - BSP layout with draggable tiles
2. **Kanban** - Columns by category/type
3. **Graph** - D3.js force-directed visualization

Terminal limitations:
- Fixed character grid (no pixel positioning)
- No mouse dragging (keyboard navigation)
- Limited colors (256 at best)

### CLI View Adaptations

#### 1. List View (Default)

```
┌─ Project: Research Notes ────────────────────────────────────┐
│                                                               │
│  Filter: [all types ▼] [all categories ▼] [search...       ] │
│                                                               │
│  > [task]      ★ Review the quarterly report            3h   │
│    [idea]        Consider switching to GraphQL           1d   │
│    [question]    Why does the cache invalidate?          2d   │
│    [claim]       Performance improved by 40%             3d   │
│    [entity]      PostgreSQL database cluster             1w   │
│                                                               │
│  ↑/↓: Navigate  Enter: Edit  n: New  d: Delete  /: Search   │
└───────────────────────────────────────────────────────────────┘
```

#### 2. Tree View (Connections)

Visualize the `influencedBy` graph as a tree:

```
┌─ Connection Tree ────────────────────────────────────────────┐
│                                                               │
│  [claim] Performance improved by 40%                         │
│  ├── [entity] PostgreSQL database cluster                    │
│  │   └── [note] Migrated from MySQL last quarter             │
│  ├── [task] Implement connection pooling                     │
│  │   └── [reference] PgBouncer documentation                 │
│  └── [idea] Consider read replicas                           │
│                                                               │
│  [question] Why does the cache invalidate?                   │
│  └── [claim] TTL set to 5 minutes                            │
│      └── [counterpoint] Too aggressive for our use case      │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

#### 3. Kanban View (Columns)

```
┌─ Kanban: By Content Type ─────────────────────────────────────┐
│                                                                │
│  TASKS (3)        │ IDEAS (5)        │ QUESTIONS (2)          │
│ ─────────────────────────────────────────────────────────────  │
│  ★ Review report  │  GraphQL switch  │  Cache invalidation?   │
│    Fix tests      │  New UI layout   │  Scaling strategy?     │
│    Deploy v2      │  ML integration  │                        │
│                   │  Dark mode       │                        │
│                   │  Mobile app      │                        │
│                                                                │
│  ←/→: Switch column  ↑/↓: Navigate  Tab: Cycle view           │
└────────────────────────────────────────────────────────────────┘
```

#### 4. ASCII Graph View

For connection visualization using asciichart patterns:

```
┌─ Connection Graph ───────────────────────────────────────────┐
│                                                               │
│                    ┌─────────────┐                           │
│                    │   claim:    │                           │
│              ┌────▶│  Perf +40%  │◀────┐                     │
│              │     └─────────────┘     │                     │
│              │            │            │                     │
│              │            ▼            │                     │
│     ┌────────┴───┐  ┌──────────┐  ┌───┴────────┐            │
│     │  entity:   │  │  task:   │  │   idea:    │            │
│     │  PostgreSQL│  │ Pooling  │  │  Replicas  │            │
│     └────────────┘  └──────────┘  └────────────┘            │
│                                                               │
│  Nodes: 5  Edges: 4  Clusters: 1                             │
└───────────────────────────────────────────────────────────────┘
```

### Implementation with Ink

```tsx
// packages/cli/src/components/TreeView.tsx
import { Box, Text } from 'ink';
import { TextBlock } from '@nodepad/core';

interface TreeNode {
  block: TextBlock;
  children: TreeNode[];
}

function TreeView({ roots }: { roots: TreeNode[] }) {
  return (
    <Box flexDirection="column">
      {roots.map(root => (
        <TreeBranch key={root.block.id} node={root} depth={0} />
      ))}
    </Box>
  );
}

function TreeBranch({ node, depth }: { node: TreeNode; depth: number }) {
  const prefix = depth === 0 ? '' : '│  '.repeat(depth - 1) + '├── ';
  
  return (
    <Box flexDirection="column">
      <Text>
        {prefix}
        <Text color="cyan">[{node.block.contentType}]</Text>
        {' '}{node.block.text.slice(0, 50)}
      </Text>
      {node.children.map((child, i) => (
        <TreeBranch 
          key={child.block.id} 
          node={child} 
          depth={depth + 1} 
        />
      ))}
    </Box>
  );
}
```

---

## AI Integration Patterns

### Streaming Responses in Terminal

The web version uses streaming for AI responses. Terminal requires special handling:

```typescript
// packages/cli/src/ai/stream-handler.ts
import ora from 'ora';
import { streamEnrichBlock } from '@nodepad/core';

export async function enrichBlockWithFeedback(
  block: TextBlock,
  settings: AISettings
): Promise<TextBlock> {
  const spinner = ora({
    text: 'Analyzing content...',
    spinner: 'dots'
  }).start();
  
  try {
    let lastUpdate = '';
    
    const enriched = await streamEnrichBlock(block, settings, {
      onProgress: (partial) => {
        // Update spinner text with streaming content
        if (partial.contentType && partial.contentType !== lastUpdate) {
          spinner.text = `Detected type: ${partial.contentType}`;
          lastUpdate = partial.contentType;
        }
      }
    });
    
    spinner.succeed(`Classified as: ${enriched.contentType}`);
    return enriched;
    
  } catch (error) {
    spinner.fail('Classification failed');
    throw error;
  }
}
```

### Background Processing

For ghost note generation (which can take 10-30 seconds):

```typescript
// packages/cli/src/ai/background.ts
import { Worker, isMainThread, parentPort } from 'worker_threads';

export function generateGhostNotesBackground(
  projectId: string,
  onProgress: (status: string) => void
): Promise<GhostNote[]> {
  return new Promise((resolve, reject) => {
    const worker = new Worker('./ghost-worker.js', {
      workerData: { projectId }
    });
    
    worker.on('message', (msg) => {
      if (msg.type === 'progress') {
        onProgress(msg.status);
      } else if (msg.type === 'complete') {
        resolve(msg.ghostNotes);
      }
    });
    
    worker.on('error', reject);
  });
}
```

### API Key Management

```typescript
// packages/cli/src/config/api-keys.ts
import Conf from 'conf';
import { createCipheriv, createDecipheriv } from 'crypto';

const config = new Conf({
  projectName: 'nodepad',
  encryptionKey: getSystemKey() // Derived from machine ID
});

export const apiKeyManager = {
  set(provider: string, key: string) {
    config.set(`apiKeys.${provider}`, encrypt(key));
  },
  
  get(provider: string): string | null {
    const encrypted = config.get(`apiKeys.${provider}`);
    return encrypted ? decrypt(encrypted) : null;
  },
  
  list(): string[] {
    const keys = config.get('apiKeys') || {};
    return Object.keys(keys);
  }
};
```

### CLI AI Commands

```
nodepad config set-api-key openai sk-...
nodepad config set-api-key openrouter sk-or-...
nodepad config set-model gpt-4

nodepad enrich <block-id>           # Classify single block
nodepad enrich --all                # Classify all unclassified
nodepad ghost                       # Generate ghost notes
nodepad ghost --watch               # Auto-generate on changes
```

---

## Recommended Architecture

### Monorepo Structure

```
nodepad/
├── packages/
│   ├── core/                      # @nodepad/core
│   │   ├── src/
│   │   │   ├── types/             # Shared TypeScript interfaces
│   │   │   ├── ai/                # AI integration (provider-agnostic)
│   │   │   ├── operations/        # Business logic
│   │   │   └── storage/           # Storage interface
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   ├── web/                       # Next.js app (existing, restructured)
│   │   ├── app/
│   │   ├── components/
│   │   ├── lib/
│   │   │   └── storage/
│   │   │       └── local-storage.ts
│   │   └── package.json
│   │
│   └── cli/                       # @nodepad/cli (new)
│       ├── src/
│       │   ├── commands/          # CLI command handlers
│       │   ├── components/        # Ink React components
│       │   ├── storage/           # SQLite adapter
│       │   └── index.tsx          # Entry point
│       ├── bin/
│       │   └── nodepad.js
│       └── package.json
│
├── package.json                   # Workspace root
├── pnpm-workspace.yaml
└── turbo.json                     # Turborepo config
```

### Package Dependencies

```json
// packages/core/package.json
{
  "name": "@nodepad/core",
  "dependencies": {
    "zod": "^3.x"               // Schema validation
  },
  "peerDependencies": {
    "openai": "^4.x"            // AI SDK (optional)
  }
}

// packages/cli/package.json
{
  "name": "@nodepad/cli",
  "bin": {
    "nodepad": "./bin/nodepad.js"
  },
  "dependencies": {
    "@nodepad/core": "workspace:*",
    "ink": "^5.x",
    "ink-text-input": "^6.x",
    "better-sqlite3": "^11.x",
    "ora": "^8.x",
    "chalk": "^5.x",
    "commander": "^12.x",
    "conf": "^13.x"
  }
}
```

---

## Implementation Roadmap

### Phase 1: Core Extraction (Week 1-2)

- [ ] Set up monorepo with pnpm workspaces + Turborepo
- [ ] Extract types to `@nodepad/core`
- [ ] Extract business logic (block ops, search, connections)
- [ ] Extract AI integration with provider abstraction
- [ ] Define `StorageAdapter` interface
- [ ] Update web app to use `@nodepad/core`
- [ ] Add tests for core package

### Phase 2: CLI Foundation (Week 2-3)

- [ ] Set up Ink CLI project structure
- [ ] Implement SQLite storage adapter
- [ ] Build basic CRUD commands
- [ ] Create List view component
- [ ] Add keyboard navigation
- [ ] Implement search/filter

### Phase 3: Views & Navigation (Week 3-4)

- [ ] Build Tree view (connection graph)
- [ ] Build Kanban view
- [ ] Implement view switching
- [ ] Add block editor (inline and full-screen)
- [ ] Implement project switching

### Phase 4: AI Integration (Week 4-5)

- [ ] Port AI enrichment with streaming
- [ ] Add ora spinners for feedback
- [ ] Implement ghost note generation
- [ ] Background processing with workers
- [ ] API key configuration

### Phase 5: Polish & Sync (Week 5-6)

- [ ] Import/export `.nodepad` files
- [ ] Bidirectional sync with web
- [ ] Error handling and recovery
- [ ] Help system and documentation
- [ ] Performance optimization
- [ ] Release and packaging

---

## Appendix: Reference CLI Tools Analyzed

### nb (Note-taking CLI)
- Single shell script, ~7000 lines
- Git-backed, plain text + encryption
- Excellent UX patterns for note linking
- https://github.com/xwmx/nb

### Ink Ecosystem
- `ink` - React renderer (37.4k stars)
- `ink-text-input` - Text input component
- `ink-select-input` - Selection lists
- `ink-spinner` - Loading spinners
- `ink-table` - Table rendering

### Visualization Libraries
- `blessed-contrib` - Dashboard widgets (15.7k stars)
- `asciichart` - ASCII line charts (2.1k stars)
- `cli-table3` - Unicode tables
- `boxen` - Terminal boxes

### Storage
- `better-sqlite3` - Synchronous SQLite (7.1k stars)
- `conf` - Simple config storage
- `keytar` - Secure credential storage

---

## Conclusion

Building a CLI version of Nodepad is feasible and offers significant benefits:

1. **Offline-first** - Works without browser, stores locally
2. **Integration** - Pipe notes, scripts, automation
3. **Speed** - Instant startup, keyboard-driven
4. **Portability** - SSH into any machine

The recommended approach maximizes code reuse through a shared core library while leveraging Ink's React foundation for familiar development patterns. The estimated 4-6 week timeline delivers a functional MVP with room for iterative enhancement.
