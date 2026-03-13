# Replace DaisyUI + HEEx with live_react + shadcn/ui

## Context

FlyCode is a Phoenix LiveView app started today. The current frontend uses HEEx templates + DaisyUI for styling. The goal is to replace the entire frontend rendering layer with React + shadcn/ui via the `live_react` library, while keeping LiveView as the state management and routing layer.

**Motivation:**
- shadcn/ui provides a more polished, modern UI aesthetic than DaisyUI
- React + TypeScript offers a better developer experience and richer component model than HEEx
- React ecosystem unlocks richer client-side interactivity (animations, drag-drop, rich text, etc.)
- Since the project just started, there is zero migration cost — this is a greenfield replacement

## Architecture Overview

LiveView remains the server-side state owner. React handles all rendering. The `live_react` library bridges them — LiveView assigns become React props (pushed reactively via WebSocket), and React pushes events back to LiveView via `pushEvent`.

```
Browser (React + shadcn/ui)
  ↕ live_react bridge (WebSocket props/events)
Phoenix LiveView (state, routing, auth)
  ↕ PubSub
FLAME Runners (agent sessions)
```

## Build Pipeline

### Remove
- `esbuild` hex package from mix.exs deps
- `tailwind` hex package from mix.exs deps
- `heroicons` github dep from mix.exs deps
- `assets/vendor/` directory entirely (daisyui.js, daisyui-theme.js, heroicons.js, topbar.js)
- Custom ScrollBottom JS hook from app.js (React handles this natively)
- esbuild config block from `config/config.exs` (lines 25-33)
- tailwind config block from `config/config.exs` (lines 35-44)
- esbuild/tailwind watchers from `config/dev.exs` (line 27-29)

### Add
- `live_react` hex package
- npm: `vite`, `@vitejs/plugin-react`, `react`, `react-dom`, `live_react` (JS package)
- npm: `tailwindcss`, `@tailwindcss/vite` (Tailwind v4 via Vite plugin)
- npm: `lucide-react` (shadcn's default icon library, replaces Heroicons)
- npm: `topbar` (keep page navigation progress indicator, import via npm instead of vendor)
- shadcn/ui CLI + components (copy-paste, not a runtime dependency)
- TypeScript: `typescript`, `@types/react`, `@types/react-dom`

### Vite Configuration (assets/vite.config.ts)

```typescript
import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"
import liveReactPlugin from "live_react/vite-plugin"

export default defineConfig(({ command }) => ({
  publicDir: "static",
  plugins: [
    liveReactPlugin(),
    react(),
    tailwindcss(),
  ],
  build: {
    target: "es2022",
    outDir: "../priv/static/assets",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        app: "./js/app.js",
      },
      output: {
        entryFileNames: "[name].js",
        chunkFileNames: "[name]-[hash].js",
        assetFileNames: "[name][extname]",
      },
    },
  },
  resolve: {
    alias: {
      "@": "./react-components",
    },
  },
}))
```

### app.js Integration

```javascript
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "topbar"
import { getHooks } from "live_react"
import components from "../react-components"
import "../css/app.css"

const hooks = {
  ...getHooks(components),
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: hooks,
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
```

### Component Registry (assets/react-components/index.ts)

```typescript
import HomeDashboard from "./HomeDashboard"
import ProjectShow from "./ProjectShow"
import ProjectNew from "./ProjectNew"
import EnvVarManager from "./EnvVarManager"
import GlobalEnvManager from "./GlobalEnvManager"
import SessionChat from "./SessionChat"

export default {
  HomeDashboard,
  ProjectShow,
  ProjectNew,
  EnvVarManager,
  GlobalEnvManager,
  SessionChat,
}
```

### Mix Aliases (mix.exs)

```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
    "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
    "assets.setup": ["cmd --cd assets npm install"],
    "assets.build": ["compile", "cmd --cd assets npm run build"],
    "assets.deploy": ["cmd --cd assets npm run build", "phx.digest"],
    precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
  ]
end
```

### Dev Watcher (config/dev.exs)

```elixir
watchers: [
  npm: ["run", "dev", cd: Path.expand("../assets", __DIR__)]
]
```

### Live Reload Patterns (config/dev.exs)

Update to also watch React component changes:

```elixir
live_reload: [
  web_console_logger: true,
  patterns: [
    ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
    ~r"priv/gettext/.*\.po$",
    ~r"lib/fly_code_web/router\.ex$",
    ~r"lib/fly_code_web/(controllers|live|components)/.*\.(ex|heex)$"
  ]
]
```

Note: React HMR is handled by Vite directly, not Phoenix live_reload. The patterns above still cover LiveView changes (which trigger full reconnect). Vite HMR handles `.tsx` changes without page reload.

### Dockerfile Changes

Add Node.js to the builder stage and run npm build:

```dockerfile
FROM ${BUILDER_IMAGE} as builder

# install build dependencies (add nodejs)
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# ... (existing hex/rebar/deps steps) ...

COPY assets assets

# Install npm deps and compile assets
RUN cd assets && npm ci
RUN mix compile
RUN mix assets.deploy
```

The runner stage already has Node.js installed (for Claude Code). No changes needed there.

## Directory Structure

```
assets/
├── css/
│   └── app.css              # Tailwind v4 with @theme inline (shadcn CSS vars, OKLCH)
├── js/
│   └── app.js               # LiveSocket + live_react hooks
├── react-components/
│   ├── index.ts              # Component registry (exports all components)
│   ├── ui/                   # shadcn/ui primitives (Button, Input, Card, etc.)
│   ├── types.ts              # Shared TypeScript types for LiveView props
│   ├── HomeDashboard.tsx
│   ├── ProjectShow.tsx
│   ├── ProjectNew.tsx
│   ├── EnvVarManager.tsx
│   ├── GlobalEnvManager.tsx
│   └── SessionChat/
│       ├── index.tsx
│       ├── MessageList.tsx
│       ├── MessageBubble.tsx
│       ├── ToolUseBlock.tsx
│       ├── StreamingIndicator.tsx
│       ├── ChatInput.tsx
│       └── StatusBadge.tsx
├── lib/
│   └── utils.ts              # shadcn cn() utility
├── components.json           # shadcn config
├── package.json
├── tsconfig.json
└── vite.config.ts
```

## Layout Strategy

The Phoenix layout (`layouts.ex`) **stays as HEEx**. It provides the HTML shell, nav bar, and wraps `@inner_content`. Each LiveView renders a `<.react>` component inside that layout.

```
layouts.ex (HEEx) — html, head, nav, body shell
  └── LiveView render — <.react name="PageComponent" ...props />
        └── React component — full page content
```

Flash messages transition from the HEEx `<.flash_group>` to Sonner (React toast). The layout removes `<.flash_group>` and instead renders a Sonner `<Toaster>` via a small React mount point:

```elixir
# In layouts.ex app layout
<.react name="Toaster" />
<main>
  {@inner_content}
</main>
```

LiveViews push toast events via `push_event(socket, "toast", %{...})` instead of `put_flash`.

## Component Architecture

### LiveView → React Mapping

Each LiveView becomes a thin state controller rendering one top-level `<.react>` component:

| LiveView | React Component | Notes |
|----------|----------------|-------|
| HomeLive | `HomeDashboard.tsx` | Lists projects + active sessions |
| ProjectLive.New | `ProjectNew.tsx` | Form with validation |
| ProjectLive.Show | `ProjectShow.tsx` | Project detail, session table, start button |
| EnvVarLive | `EnvVarManager.tsx` | CRUD table, file upload, reveal/hide |
| GlobalEnvLive | `GlobalEnvManager.tsx` | Shares sub-components with EnvVarManager |
| SessionLive | `SessionChat.tsx` | Streaming chat, tool use, status transitions |

### LiveView Template Pattern

All LiveViews follow the same minimal pattern:

```elixir
def render(assigns) do
  ~H"""
  <.react name="HomeDashboard" projects={@projects} sessions={@sessions} />
  """
end
```

All rendering logic, conditionals, and styling lives in React.

### TypeScript Prop Types (assets/react-components/types.ts)

```typescript
export interface Project {
  id: string
  name: string
  repo_url: string
  inserted_at: string
}

export interface Session {
  id: string
  status: "cloning" | "active" | "idle" | "shutdown"
  backend: "claude_code" | "opencode"
  project_id: string
  inserted_at: string
}

export interface Message {
  id: string
  role: "user" | "assistant" | "tool" | "error"
  content: string
  tool_name?: string
  tool_input?: string
  tool_result?: string
}

export interface EnvVar {
  id: string
  key: string
  value: string
  scope: "global" | "project"
}
```

### Icons

Replace Heroicons with `lucide-react` (shadcn's default). Usage:

```tsx
import { Plus, Trash2, Eye, EyeOff } from "lucide-react"
// <Plus className="h-4 w-4" />
```

### shadcn/ui Primitives Used

| shadcn Component | Used In |
|-----------------|---------|
| Button | Everywhere |
| Input, Textarea | ProjectNew, SessionChat, EnvVar |
| Table | ProjectShow, EnvVar, GlobalEnv, HomeDashboard |
| Card | HomeDashboard, ProjectShow |
| Badge | Session status indicators |
| Collapsible | Tool use output in SessionChat |
| Dialog | Confirm delete, env var edit |
| DropdownMenu | Session actions, project actions |
| ScrollArea | Chat message container |
| Sonner (toast) | Flash message replacement |

### Shared Sub-Components

EnvVarManager and GlobalEnvManager share:
- `EnvVarTable.tsx` — table with reveal/hide, edit, delete
- `EnvVarForm.tsx` — create/edit form with file upload support

### SessionChat Sub-Components

```
SessionChat/
├── index.tsx              # Main chat container
├── MessageList.tsx        # ScrollArea with auto-scroll
├── MessageBubble.tsx      # Renders user/assistant/error messages
├── ToolUseBlock.tsx       # Collapsible tool invocation display
├── StreamingIndicator.tsx # Animated typing cursor
├── ChatInput.tsx          # Textarea + send button
└── StatusBadge.tsx        # cloning/active/idle/shutdown
```

## Data Flow

### LiveView → React (props)

Any assign passed as an attribute to `<.react>` becomes a React prop. When the assign changes server-side, live_react pushes the new value via WebSocket and React re-renders.

```elixir
<.react
  name="SessionChat"
  messages={@messages}
  status={@status}
  streaming_text={@streaming_text}
  tool_uses={@tool_uses}
  session_id={@session.id}
/>
```

### React → LiveView (events)

```tsx
import { useLiveEvent } from "live_react"

function SessionChat({ messages, status }: SessionChatProps) {
  const { pushEvent } = useLiveEvent()
  const sendMessage = (text: string) => pushEvent("send_message", { content: text })
  // ...
}
```

Existing `handle_event` callbacks in LiveViews remain unchanged.

### Streaming Chat Flow

```
FLAME Runner (SessionManager)
  → PubSub broadcast {:text_delta, "hello"}
    → SessionLive handle_info
      → assign(socket, streaming_text: updated_text)
        → live_react pushes new streaming_text prop
          → SessionChat re-renders with updated text
```

The Elixir side (PubSub subscriptions, handle_info callbacks, status transitions) stays exactly as-is. Only the rendering layer changes.

### Auto-Scroll

Replaces the custom ScrollBottom hook with React:

```tsx
const bottomRef = useRef<HTMLDivElement>(null)
useEffect(() => {
  bottomRef.current?.scrollIntoView({ behavior: "smooth" })
}, [messages, streaming_text])
```

### Error Boundaries

Wrap each page-level React component in a React error boundary so a component crash shows a fallback UI instead of killing the LiveView connection:

```tsx
// In the component registry or a wrapper
<ErrorBoundary fallback={<div>Something went wrong. Refresh to retry.</div>}>
  <PageComponent {...props} />
</ErrorBoundary>
```

## Collections Strategy

LiveView streams are not supported as live_react props (on their roadmap). All collections are passed as regular assign lists. For large collections, paginate server-side. The CLAUDE.md rule about "always use streams" is suspended for React-rendered collections — React handles efficient list rendering via keys natively.

## Known Limitations

- **LiveView streams not supported as props** — live_react's roadmap item. Not a blocker since collections are small and React handles list rendering efficiently via keys.
- **No `useLiveForm`** — Ecto changeset integration is on live_react's roadmap. For now, forms use `pushEvent` for submission and receive validation errors as props.
- **SSR optional** — Can be enabled later via `LiveReact.SSR.NodeJS` in prod config. Not needed initially. Note: without SSR, there's a brief flash before React hydrates. Acceptable for an internal tool.
- **live_react maturity** — 253 stars, 70 commits, MIT licensed. Young but actively maintained. The API surface is small, reducing risk.

## Config & CLAUDE.md Updates

After implementation, update CLAUDE.md to reflect:
- Vite replaces esbuild + tailwind hex packages
- React + TypeScript for all UI rendering
- shadcn/ui + lucide-react replaces DaisyUI + Heroicons
- HEEx templates are minimal (just `<.react>` calls) — layout stays as HEEx
- Forms use pushEvent, not changesets-to-forms
- Collections as regular assigns (no streams rule for React)
- `npm run dev` / `npm run build` for asset pipeline
- Remove all DaisyUI, Heroicons, HEEx-specific rules

## Testing Strategy

- **React components:** Vitest + React Testing Library for unit tests of individual components
- **LiveView integration:** ExUnit tests focus on the LiveView layer — testing `handle_event`, `handle_info`, assigns. These don't assert on rendered HTML (since it's just a `<.react>` tag). Test event handling and state transitions.
- **E2E:** Playwright for full browser testing of React rendering + LiveView state together. This is the primary way to test the complete user experience.
- **Existing LiveViewTest DOM assertions** (e.g., `has_element?/2`) will no longer match React-rendered content. These tests should be converted to either ExUnit assign assertions or Playwright E2E tests.
