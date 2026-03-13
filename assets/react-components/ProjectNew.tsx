import { useState, useEffect } from "react"
import { Link } from "live_react"
import { useLiveReact } from "live_react"
import { ArrowLeft } from "lucide-react"
import { Button } from "@/ui/button"
import { Input } from "@/ui/input"
import { Card, CardHeader, CardTitle, CardContent } from "@/ui/card"

interface ProjectNewProps {
  form: {
    name: string
    repo_url: string
    default_branch: string
    errors: Record<string, string[]>
  }
}

export default function ProjectNew({ form }: ProjectNewProps) {
  const { pushEvent } = useLiveReact()
  const [formData, setFormData] = useState({
    name: form.name || "",
    repo_url: form.repo_url || "",
    default_branch: form.default_branch || "main",
  })

  useEffect(() => {
    setFormData({
      name: form.name || "",
      repo_url: form.repo_url || "",
      default_branch: form.default_branch || "main",
    })
  }, [form.name, form.repo_url, form.default_branch])

  const handleChange = (field: string, value: string) => {
    const updated = { ...formData, [field]: value }
    setFormData(updated)
    pushEvent("validate", { project: updated })
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    pushEvent("save", { project: formData })
  }

  const getErrors = (field: string): string[] => {
    return form.errors?.[field] || []
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6 p-6">
      <Link navigate="/">
        <Button variant="ghost" size="sm">
          <ArrowLeft className="h-4 w-4" />
          Back
        </Button>
      </Link>

      <Card>
        <CardHeader>
          <CardTitle>New Project</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <label htmlFor="name" className="text-sm font-medium">
                Project Name
              </label>
              <Input
                id="name"
                value={formData.name}
                onChange={(e) => handleChange("name", e.target.value)}
                placeholder="my-project"
              />
              {getErrors("name").map((err, i) => (
                <p key={i} className="text-sm text-destructive">{err}</p>
              ))}
            </div>

            <div className="space-y-2">
              <label htmlFor="repo_url" className="text-sm font-medium">
                Repository URL
              </label>
              <Input
                id="repo_url"
                value={formData.repo_url}
                onChange={(e) => handleChange("repo_url", e.target.value)}
                placeholder="https://github.com/user/repo.git"
              />
              {getErrors("repo_url").map((err, i) => (
                <p key={i} className="text-sm text-destructive">{err}</p>
              ))}
            </div>

            <div className="space-y-2">
              <label htmlFor="default_branch" className="text-sm font-medium">
                Default Branch
              </label>
              <Input
                id="default_branch"
                value={formData.default_branch}
                onChange={(e) => handleChange("default_branch", e.target.value)}
                placeholder="main"
              />
              {getErrors("default_branch").map((err, i) => (
                <p key={i} className="text-sm text-destructive">{err}</p>
              ))}
            </div>

            <div className="flex justify-end gap-2 pt-4">
              <Link navigate="/">
                <Button type="button" variant="outline">
                  Cancel
                </Button>
              </Link>
              <Button type="submit">Create Project</Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
