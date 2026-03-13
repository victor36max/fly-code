import { useState } from "react"
import { Link } from "live_react"
import { useLiveReact } from "live_react"
import { ArrowLeft, Eye, EyeOff, Trash2, Plus } from "lucide-react"
import { Button } from "@/ui/button"
import { Input } from "@/ui/input"
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/ui/card"
import type { EnvVar } from "./types"

interface EnvVarManagerProps {
  project: { id: number; name: string } | null
  env_vars: EnvVar[]
  scope: "project" | "global"
  revealed: number[]
  new_key: string
  new_value: string
}

export default function EnvVarManager({
  project,
  env_vars,
  scope,
  revealed,
  new_key,
  new_value,
}: EnvVarManagerProps) {
  const { pushEvent } = useLiveReact()
  const [key, setKey] = useState(new_key || "")
  const [value, setValue] = useState(new_value || "")

  const revealedSet = new Set(revealed || [])
  const backPath = scope === "global" ? "/" : `/projects/${project?.id}`
  const title = scope === "global" ? "Global Environment Variables" : `${project?.name} - Environment Variables`

  const handleAdd = (e: React.FormEvent) => {
    e.preventDefault()
    if (!key.trim()) return
    pushEvent("add_var", { key: key.trim(), value })
    setKey("")
    setValue("")
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6 p-6">
      <Link navigate={backPath}>
        <Button variant="ghost" size="sm">
          <ArrowLeft className="h-4 w-4" />
          Back
        </Button>
      </Link>

      <h1 className="text-2xl font-bold">{title}</h1>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Variables</CardTitle>
          <CardDescription>
            {env_vars.length === 0
              ? "No environment variables configured."
              : `${env_vars.length} variable${env_vars.length === 1 ? "" : "s"}`}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {env_vars.map((envVar) => (
            <div
              key={envVar.id}
              className="flex items-center gap-3 rounded-md border p-3"
            >
              <code className="min-w-0 flex-1 truncate text-sm font-semibold">
                {envVar.key}
              </code>
              <code className="min-w-0 flex-1 truncate text-sm text-muted-foreground">
                {revealedSet.has(envVar.id) ? envVar.value : "••••••••"}
              </code>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => pushEvent("toggle_reveal", { id: envVar.id })}
                title={revealedSet.has(envVar.id) ? "Hide" : "Reveal"}
              >
                {revealedSet.has(envVar.id) ? (
                  <EyeOff className="h-4 w-4" />
                ) : (
                  <Eye className="h-4 w-4" />
                )}
              </Button>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => pushEvent("delete_var", { id: envVar.id })}
                className="text-destructive hover:text-destructive"
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Add Variable</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleAdd} className="flex items-end gap-3">
            <div className="flex-1 space-y-1">
              <label htmlFor="env-key" className="text-xs font-medium">
                Key
              </label>
              <Input
                id="env-key"
                value={key}
                onChange={(e) => setKey(e.target.value)}
                placeholder="MY_VARIABLE"
              />
            </div>
            <div className="flex-1 space-y-1">
              <label htmlFor="env-value" className="text-xs font-medium">
                Value
              </label>
              <Input
                id="env-value"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                placeholder="secret-value"
              />
            </div>
            <Button type="submit" disabled={!key.trim()}>
              <Plus className="h-4 w-4" />
              Add
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
