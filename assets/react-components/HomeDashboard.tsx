import { Link } from "live_react"
import { Plus, Globe, ExternalLink } from "lucide-react"
import { Button } from "@/ui/button"
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/ui/card"
import { Badge } from "@/ui/badge"
import type { Project } from "./types"

interface ActiveSession {
  session_id: string
  project_name?: string
  backend?: string
  status?: string
}

interface HomeDashboardProps {
  projects: Project[]
  active_sessions: Record<string, ActiveSession>
}

export default function HomeDashboard({ projects, active_sessions }: HomeDashboardProps) {
  const sessionEntries = Object.entries(active_sessions || {})

  return (
    <div className="mx-auto max-w-4xl space-y-8 p-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold tracking-tight">FlyCode</h1>
        <Link navigate="/projects/new">
          <Button>
            <Plus className="h-4 w-4" />
            New Project
          </Button>
        </Link>
      </div>

      {sessionEntries.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">Active Sessions</h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {sessionEntries.map(([id, session]) => (
              <Card key={id}>
                <CardHeader className="pb-3">
                  <div className="flex items-center justify-between">
                    <CardTitle className="text-sm font-medium">
                      {session.project_name || "Session"}
                    </CardTitle>
                    <Badge variant="default" className="animate-pulse">
                      live
                    </Badge>
                  </div>
                  {session.backend && (
                    <CardDescription>{session.backend}</CardDescription>
                  )}
                </CardHeader>
                <CardContent>
                  <Link navigate={`/session/${id}`}>
                    <Button variant="outline" size="sm" className="w-full">
                      <ExternalLink className="h-3 w-3" />
                      Open
                    </Button>
                  </Link>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>
      )}

      <section className="space-y-4">
        <h2 className="text-xl font-semibold">Projects</h2>
        {projects.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center justify-center py-12">
              <p className="mb-4 text-muted-foreground">No projects yet</p>
              <Link navigate="/projects/new">
                <Button variant="outline">
                  <Plus className="h-4 w-4" />
                  Create your first project
                </Button>
              </Link>
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {projects.map((project) => (
              <Link key={project.id} navigate={`/projects/${project.id}`}>
                <Card className="cursor-pointer transition-colors hover:bg-accent/50">
                  <CardHeader>
                    <CardTitle className="text-base">{project.name}</CardTitle>
                    <CardDescription className="truncate text-xs">
                      {project.repo_url}
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <Badge variant="secondary">{project.default_branch}</Badge>
                  </CardContent>
                </Card>
              </Link>
            ))}
          </div>
        )}
      </section>

      <div className="border-t pt-4">
        <Link navigate="/settings/env">
          <Button variant="ghost" className="text-muted-foreground">
            <Globe className="h-4 w-4" />
            Global Environment Variables
          </Button>
        </Link>
      </div>
    </div>
  )
}
