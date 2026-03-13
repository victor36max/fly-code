import { Link } from "live_react"
import { useLiveReact } from "live_react"
import { ArrowLeft } from "lucide-react"
import { Button } from "@/ui/button"
import { Badge } from "@/ui/badge"
import StatusBadge from "./StatusBadge"
import MessageList from "./MessageList"
import ChatInput from "./ChatInput"
import type { Message } from "../types"

interface SessionChatProps {
  session_id: string
  db_session: {
    project?: { name: string }
  } | null
  status: string
  backend: string
  messages: Message[]
  current_text: string
  streaming: boolean
  input_text: string
}

export default function SessionChat({
  session_id,
  db_session,
  status,
  backend,
  messages,
  current_text,
  streaming,
  input_text,
}: SessionChatProps) {
  const { pushEvent } = useLiveReact()

  const projectName = db_session?.project?.name
  const inputDisabled = streaming || (status !== "active" && status !== "idle")

  const displayMessages = [...messages]
  if (current_text) {
    displayMessages.push({
      id: -1,
      role: "assistant",
      content: current_text,
    })
  }

  return (
    <div className="flex h-screen flex-col">
      <header className="flex items-center gap-3 border-b px-4 py-3">
        <Link navigate={projectName ? "/" : "/"}>
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-4 w-4" />
          </Button>
        </Link>

        <div className="flex min-w-0 flex-1 items-center gap-3">
          {projectName && (
            <span className="truncate font-medium">{projectName}</span>
          )}
          <span className="truncate font-mono text-xs text-muted-foreground">
            {session_id.slice(0, 8)}
          </span>
        </div>

        <div className="flex items-center gap-2">
          <StatusBadge status={status} />
          <Badge variant="outline">{backend}</Badge>
        </div>
      </header>

      <MessageList
        messages={displayMessages}
        streaming={streaming}
        status={status}
      />

      <ChatInput
        inputText={input_text}
        disabled={inputDisabled}
        onSend={(text) => pushEvent("send_message", { text })}
        onUpdateInput={(text) => pushEvent("update_input", { text })}
      />
    </div>
  )
}
