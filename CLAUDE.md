# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

FlyCode is a Phoenix LiveView app that spawns remote AI agent sessions (Claude Code / OpenCode) on isolated FLAME runners. Users register git repos as "projects," configure encrypted env vars, then start agent sessions that clone the repo on a FLAME worker and stream real-time chat via PubSub.

## Common Commands

```bash
mix setup                # Install deps, create DB, migrate, build assets
mix phx.server           # Start dev server (localhost:4000)
mix test                 # Create/migrate test DB, run all tests
mix test test/path.exs   # Run a single test file
mix test --failed        # Re-run previously failed tests
mix precommit            # Compile (warnings-as-errors), check deps, format, test
mix format               # Format code
mix ecto.gen.migration name  # Generate a new migration
mix ecto.migrate         # Run pending migrations
cd assets && pnpm install    # Install JS dependencies
cd assets && pnpm run build  # Build assets manually
```

Docker Compose provides PostgreSQL: `docker compose up -d`

## Architecture

### Core Domain (`lib/fly_code/`)

- **`projects/`** — `Project` and `EnvVar` schemas + context functions. EnvVars are AES-encrypted via Cloak (`vault.ex`). Env vars have `:global` or `:project` scope; project vars override globals on merge.
- **`sessions/`** — `Session` schema tracking status (`:cloning` → `:active` → `:idle` → `:shutdown`) and backend (`:claude_code` | `:opencode`).
- **`agent/coordinator.ex`** — GenServer on the main VM. Maps session IDs to remote FLAME pids. Handles `start_session`, `send_message`, `stop_session`.
- **`agent/session_manager.ex`** — GenServer running on FLAME runners. Owns the agent lifecycle: clones repo via `Workspace`, starts the backend, streams events back via PubSub.
- **`agent/backends/`** — `claude_code_backend.ex` and `opencode_backend.ex` adapt each SDK to a common interface.
- **`workspace.ex`** — Git clone/pull + env var injection on runners.

### Web Layer (`lib/fly_code_web/`)

- **LiveViews in `live/`**: Thin state controllers that render React components via `<.react>`. LiveViews handle state, events, PubSub — React handles all rendering.
- **React components in `assets/react-components/`**: All UI rendering uses React + shadcn/ui via `live_react`. Components receive LiveView assigns as props and push events back via `useLiveReact()`.
- **PubSub topics**: `"session:#{session_id}"` for real-time event streaming between SessionManager and SessionLive.

### FLAME Pool

Configured in `application.ex`. Min 0, max 15 runners, 10min idle shutdown, 2min boot timeout. Backend is `FLAME.FlyBackend` in prod (set via `FLAME_BACKEND` env var).

- **FLAME runners have NO database access.** Code running on FLAME runners (e.g. `SessionManager`) cannot call `Repo`, Ecto queries, or any context function that touches the DB. All DB writes must happen on the main VM (e.g. via the Coordinator or LiveViews). Runners communicate back to the main VM exclusively through PubSub.

## Key Runtime Env Vars

`DATABASE_URL`, `SECRET_KEY_BASE`, `CLOAK_KEY` (base64 AES key), `PHX_HOST`, `FLAME_BACKEND` ("Fly" for prod), `FLY_API_TOKEN`, `GIT_TOKEN`.

## Stack & Conventions

- **Elixir 1.18.3 / OTP 27.3.4** (see `.tool-versions`)
- **Phoenix 1.8.5** with LiveView 1.1 — LiveViews are thin state controllers
- **React + TypeScript** for all UI rendering via `live_react`
- **shadcn/ui** component library + **Tailwind CSS v4** + **lucide-react** icons
- **Vite** for asset bundling (replaces esbuild/tailwind hex packages)
- **pnpm** for JS package management
- **Ecto** with PostgreSQL
- **Req** for HTTP — never use HTTPoison, Tesla, or :httpc
- Use `mix precommit` when done with all changes

## Elixir Rules

- Lists don't support index access (`mylist[i]`) — use `Enum.at/2`
- Variables are immutable; must bind `if`/`case`/`cond` results: `socket = if ... do ... end`
- Never nest multiple modules in the same file
- Never use bracket access on structs (no Access behaviour) — use `my_struct.field` or `Ecto.Changeset.get_field/2`
- Predicate functions end with `?` (not `is_` prefix); reserve `is_` for guards
- Don't use `String.to_atom/1` on user input
- Use `Task.async_stream/3` for concurrent enumeration (usually with `timeout: :infinity`)
- OTP primitives like `DynamicSupervisor` and `Registry` require names in child specs

## Phoenix / LiveView Rules

- LiveViews render React components via `<.react name="ComponentName" prop={@assign} />`
- Wrap page content in `<Layouts.app flash={@flash}>` (already aliased in `fly_code_web.ex`)
- `LiveReact` is imported in `fly_code_web.ex` html_helpers — `<.react>` is available in all LiveViews
- Serialize Elixir data (atoms, structs, MapSets) to JSON-friendly formats before passing as React props
- Router `scope` blocks alias module prefixes — don't add redundant aliases
- `Phoenix.View` is removed; don't use it
- Avoid LiveComponents unless strongly needed
- LiveView names: `AppWeb.ThingLive` suffix

### LiveView ↔ React Data Flow

- **LiveView → React**: Assigns passed as `<.react>` attributes become React props. Updates are pushed via WebSocket automatically.
- **React → LiveView**: Use `useLiveReact()` hook which returns `{ pushEvent }`. Call `pushEvent("event_name", payload)` to trigger `handle_event` in the LiveView.
- **Atoms must be serialized**: Convert atoms to strings (`Atom.to_string/1`) before passing as props. MapSets should use `MapSet.to_list/1`.
- **Collections as regular assigns**: Don't use LiveView streams for React-rendered collections. React handles efficient list rendering via keys.

### Forms

- Forms are handled in React via `pushEvent` for submission and validation
- LiveView passes form data (values + errors) as serialized props
- Ecto changeset validation still happens server-side in `handle_event`
- Fields set programmatically (e.g. `user_id`) must not be in `cast` calls
- File uploads (`live_file_input`) stay in HEEx since they require LiveView upload integration

### JS / CSS

- **Vite** bundles all JS/CSS — configured in `assets/vite.config.ts`
- **Tailwind CSS v4** with `@theme inline` for shadcn CSS variables in `assets/css/app.css`
- **shadcn/ui** components in `assets/react-components/ui/` — copy-paste, fully customizable
- **lucide-react** for icons: `import { Plus, Trash2 } from "lucide-react"`
- `assets/lib/utils.ts` has the `cn()` utility (clsx + tailwind-merge)
- Dev server: Vite provides HMR via pnpm watcher in `config/dev.exs`
- Production: `mix assets.deploy` runs `pnpm run build` + `phx.digest`
- Never write inline `<script>` tags in templates

### React Components

- Page-level components in `assets/react-components/` (one per LiveView)
- shadcn/ui primitives in `assets/react-components/ui/`
- Shared types in `assets/react-components/types.ts`
- Component registry in `assets/react-components/index.ts` — must register all page components
- Use `import { Link } from "live_react"` for LiveView navigation (`navigate`, `patch`)
- Use `import { useLiveReact } from "live_react"` for pushing events to LiveView

### Testing

- Use `start_supervised!/1` for process cleanup; avoid `Process.sleep/1` and `Process.alive?/1`
- Use `Process.monitor/1` + `assert_receive {:DOWN, ...}` instead of sleeping
- Use `:sys.get_state/1` to synchronize before assertions
- ExUnit tests focus on LiveView state/events (handle_event, handle_info, assigns)
- React component tests: Vitest + React Testing Library
- E2E tests: Playwright for full browser testing
- Run single file: `mix test test/path.exs`; rerun failures: `mix test --failed`

### Ecto

- Always preload associations accessed in templates
- Schema fields use `:string` type even for text columns
- `validate_number/2` has no `:allow_nil` option (validations skip nil by default)
- Always use `mix ecto.gen.migration` to generate migrations (correct timestamps)
- `import Ecto.Query` in seeds files
