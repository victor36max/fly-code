# Session Token Validation & Loading State

## Context

When starting a new agent session from the project page, two UX issues exist:

1. **No token validation** — Users can click "New Session" even when required tokens (GIT_TOKEN, ANTHROPIC_API_KEY / CLAUDE_CODE_OAUTH_TOKEN) are missing, leading to confusing errors deep in the FLAME runner.
2. **No loading feedback** — `starting_session: true` is set in `handle_event` but `Coordinator.start_session/2` runs synchronously, so the assign never reaches the client before navigation.

## Design

### Feature 1: Token Validation

**Required tokens by backend:**
- **All backends:** `GIT_TOKEN`
- **claude_code:** `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` (at least one)
- **opencode:** No additional token check (supports many providers)

**Backend: `Projects` context** — Add `Projects.env_var_keys(project_id)` that returns a `MapSet` of all env var key names (global + project-scoped merged) without decrypting values.

```elixir
# lib/fly_code/projects.ex
def env_var_keys(project_id) do
  global_keys = Repo.all(from e in EnvVar, where: e.scope == :global, select: e.key)
  project_keys = Repo.all(from e in EnvVar, where: e.project_id == ^project_id and e.scope == :project, select: e.key)
  MapSet.new(global_keys ++ project_keys)
end
```

**Backend: LiveView** — In `mount/3` and `handle_event("set_backend", ...)`, compute `missing_tokens` list based on the current backend and available keys.

```elixir
# lib/fly_code_web/live/project_live/show.ex
defp compute_missing_tokens(env_keys, backend) do
  missing = if MapSet.member?(env_keys, "GIT_TOKEN"), do: [], else: ["GIT_TOKEN"]

  missing ++
    case backend do
      :claude_code ->
        has_anthropic = MapSet.member?(env_keys, "ANTHROPIC_API_KEY")
        has_oauth = MapSet.member?(env_keys, "CLAUDE_CODE_OAUTH_TOKEN")
        if has_anthropic or has_oauth, do: [], else: ["ANTHROPIC_API_KEY"]

      :opencode ->
        []
    end
end
```

Pass `missing_tokens` as a serialized list prop to React.

**Frontend: Inline warning banner** — When `missing_tokens` is non-empty, show an amber alert banner above the action buttons listing what's missing, with a link to the env vars settings page. Disable the "New Session" button.

Uses a new shadcn/ui `Alert` component (needs to be added via `pnpm dlx shadcn@latest add alert`).

### Feature 2: Loading Overlay

**Backend fix: async session start** — Replace the synchronous `Coordinator.start_session` call in `handle_event` with a `send(self(), ...)` pattern:

```elixir
def handle_event("start_session", _params, socket) do
  send(self(), :do_start_session)
  {:noreply, assign(socket, starting_session: true)}
end

def handle_info(:do_start_session, socket) do
  case Coordinator.start_session(socket.assigns.project.id, backend: socket.assigns.backend) do
    {:ok, %{session_id: session_id}} ->
      {:noreply, push_navigate(socket, to: ~p"/session/#{session_id}")}
    {:error, reason} ->
      {:noreply,
       socket
       |> assign(starting_session: false)
       |> put_flash(:error, "Failed to start session: #{inspect(reason)}")}
  end
end
```

**Frontend: full-page overlay** — When `starting_session` is true, render a fixed overlay with a spinner and "Starting session..." message. Uses the existing `Loader2` icon from lucide-react with a spin animation.

## Files to Modify

| File | Change |
|------|--------|
| `lib/fly_code/projects.ex` | Add `env_var_keys/1` |
| `lib/fly_code_web/live/project_live/show.ex` | Add `compute_missing_tokens/2`, make session start async, pass `missing_tokens` prop |
| `assets/react-components/ProjectShow.tsx` | Add warning banner, loading overlay, update props interface |
| `assets/react-components/ui/alert.tsx` | Add shadcn/ui Alert component |

## Verification

1. **Token validation:**
   - Remove all env vars → warning banner shows, button disabled
   - Add GIT_TOKEN only → still disabled for claude_code (missing ANTHROPIC_API_KEY)
   - Add ANTHROPIC_API_KEY → button enabled for claude_code
   - Switch to opencode → only GIT_TOKEN required
   - Add project-scoped override → correctly reflects merged keys

2. **Loading state:**
   - Click "New Session" with valid tokens → overlay appears immediately with spinner
   - Session starts successfully → navigates to session page
   - Session fails → overlay disappears, error flash shown

3. Run `mix test` and `mix precommit`
