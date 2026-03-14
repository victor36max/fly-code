import { useState } from "react"
import { Link } from "live_react"
import { useLiveReact } from "live_react"
import CodeEditor from "@uiw/react-textarea-code-editor"
import { ArrowLeft, Plus, Settings, ExternalLink, AlertTriangle, Loader2, Pencil, Check, X, ChevronDown } from "lucide-react"
import { Button } from "@/ui/button"
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/ui/card"
import { Badge } from "@/ui/badge"
import {
  Table,
  TableHeader,
  TableBody,
  TableHead,
  TableRow,
  TableCell,
} from "@/ui/table"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/ui/dropdown-menu"
import { Alert, AlertDescription } from "@/ui/alert"
import type { Project, Session } from "./types"

interface ProjectShowProps {
  project: Project
  sessions: Session[]
  env_var_count: number
  missing_tokens: string[]
  starting_session: boolean
  backend: string
}

function statusVariant(status: string): "default" | "secondary" | "destructive" | "outline" {
  switch (status) {
    case "active":
      return "default"
    case "completed":
      return "secondary"
    case "spawning":
    case "cloning":
    case "setup_script":
    case "spawning_agent":
      return "outline"
    case "shutdown":
    case "failed":
      return "destructive"
    default:
      return "secondary"
  }
}

function formatDate(dateStr: string): string {
  try {
    return new Date(dateStr).toLocaleString()
  } catch {
    return dateStr
  }
}

const SETUP_TEMPLATES = [
  { label: "Elixir / Phoenix", script: "mix local.hex --force && mix local.rebar --force\nmix deps.get && mix compile" },
  { label: "Node.js (npm)", script: "npm install" },
  { label: "Node.js (pnpm)", script: "corepack enable && pnpm install" },
  { label: "Node.js (bun)", script: "curl -fsSL https://bun.sh/install | bash && bun install" },
  { label: "Python", script: "python3 -m venv .venv && source .venv/bin/activate\npip install -r requirements.txt" },
]

function SetupScriptCard({
  setupScript,
  onSave,
}: {
  setupScript: string | null
  onSave: (script: string) => void
}) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(setupScript || "")

  const handleEdit = () => {
    setDraft(setupScript || "")
    setEditing(true)
  }

  const handleCancel = () => {
    setDraft(setupScript || "")
    setEditing(false)
  }

  const handleSave = () => {
    onSave(draft)
    setEditing(false)
  }

  const editorStyle = {
    fontSize: 13,
    borderRadius: 6,
    fontFamily:
      "ui-monospace,SFMono-Regular,SF Mono,Consolas,Liberation Mono,Menlo,monospace",
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <CardTitle className="text-sm font-medium">Setup Script</CardTitle>
          {!editing ? (
            <Button variant="ghost" size="sm" onClick={handleEdit}>
              <Pencil className="h-3 w-3" />
              Edit
            </Button>
          ) : (
            <div className="flex gap-1">
              <Button variant="ghost" size="sm" onClick={handleCancel}>
                <X className="h-3 w-3" />
                Cancel
              </Button>
              <Button size="sm" onClick={handleSave}>
                <Check className="h-3 w-3" />
                Save
              </Button>
            </div>
          )}
        </div>
        <p className="text-xs text-muted-foreground">
          Runs on the FLAME runner after cloning the repo
        </p>
      </CardHeader>
      <CardContent>
        {editing ? (
          <div className="space-y-2">
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="outline" size="sm">
                  <ChevronDown className="h-3 w-3" />
                  Templates
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent>
                {SETUP_TEMPLATES.map((t) => (
                  <DropdownMenuItem
                    key={t.label}
                    onSelect={() => setDraft(draft ? draft + "\n" + t.script : t.script)}
                  >
                    {t.label}
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
            <CodeEditor
              value={draft}
              language="bash"
              placeholder={"#!/bin/bash\nmix deps.get && mix compile"}
              onChange={(e) => setDraft(e.target.value)}
              padding={15}
              data-color-mode="light"
              style={{
                ...editorStyle,
                border: "1px solid hsl(var(--input))",
              }}
            />
          </div>
        ) : setupScript ? (
          <CodeEditor
            value={setupScript}
            language="bash"
            readOnly
            data-color-mode="light"
            padding={15}
            style={editorStyle}
          />
        ) : (
          <p className="text-sm text-muted-foreground">No setup script configured.</p>
        )}
      </CardContent>
    </Card>
  )
}

export default function ProjectShow({
  project,
  sessions,
  env_var_count,
  missing_tokens,
  starting_session,
  backend,
}: ProjectShowProps) {
  const { pushEvent } = useLiveReact()
  const hasMissingTokens = missing_tokens.length > 0

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-6">
      {starting_session && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
          <div className="flex flex-col items-center gap-3">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
            <p className="text-sm text-muted-foreground">Starting session...</p>
          </div>
        </div>
      )}

      <Link navigate="/">
        <Button variant="ghost" size="sm">
          <ArrowLeft className="h-4 w-4" />
          Back
        </Button>
      </Link>

      <div className="space-y-1">
        <h1 className="text-2xl font-bold">{project.name}</h1>
        <p className="text-sm text-muted-foreground">{project.repo_url}</p>
      </div>

      <SetupScriptCard
        setupScript={project.setup_script}
        onSave={(script) => pushEvent("save_setup_script", { setup_script: script })}
      />

      {hasMissingTokens && (
        <Alert variant="warning">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>
            Missing required tokens: {missing_tokens.join(", ")}.{" "}
            <Link navigate={`/projects/${project.id}/env`} className="font-medium underline">
              Configure in Env Vars
            </Link>
          </AlertDescription>
        </Alert>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="sm">
              Backend: {backend}
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent>
            <DropdownMenuItem onSelect={() => pushEvent("set_backend", { backend: "claude_code" })}>
              claude_code
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => pushEvent("set_backend", { backend: "opencode" })}>
              opencode
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>

        <Button
          onClick={() => pushEvent("start_session", {})}
          disabled={starting_session || hasMissingTokens}
        >
          <Plus className="h-4 w-4" />
          {starting_session ? "Starting..." : "New Session"}
        </Button>

        <Link navigate={`/projects/${project.id}/env`}>
          <Button variant="outline" size="sm">
            <Settings className="h-4 w-4" />
            Env Vars ({env_var_count})
          </Button>
        </Link>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Sessions</CardTitle>
          <CardDescription>
            {sessions.length === 0
              ? "No sessions yet. Start one above."
              : `${sessions.length} session${sessions.length === 1 ? "" : "s"}`}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {sessions.length > 0 && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>ID</TableHead>
                  <TableHead>Backend</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Branch</TableHead>
                  <TableHead>Created</TableHead>
                  <TableHead className="text-right">Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sessions.map((session) => (
                  <TableRow key={session.id}>
                    <TableCell className="font-mono text-xs">
                      {session.session_id.slice(0, 8)}
                    </TableCell>
                    <TableCell>{session.backend}</TableCell>
                    <TableCell>
                      <Badge variant={statusVariant(session.status)}>
                        {session.status}
                      </Badge>
                    </TableCell>
                    <TableCell>{session.branch || "-"}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {formatDate(session.inserted_at)}
                    </TableCell>
                    <TableCell className="text-right">
                      <Link navigate={`/session/${session.session_id}`}>
                        <Button variant="ghost" size="sm">
                          <ExternalLink className="h-3 w-3" />
                          Open
                        </Button>
                      </Link>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
