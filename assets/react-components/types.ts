export interface Project {
  id: number
  name: string
  repo_url: string
  default_branch: string
  inserted_at: string
}

export interface Session {
  id: number
  session_id: string
  status: "cloning" | "active" | "idle" | "shutdown"
  backend: "claude_code" | "opencode"
  branch: string | null
  inserted_at: string
}

export interface Message {
  id: number
  role: "user" | "assistant" | "tool" | "error"
  content: string
  tool_name?: string
}

export interface EnvVar {
  id: number
  key: string
  value: string
  scope: "global" | "project"
}
