import { cn } from "../../lib/utils"
import { AlertCircle } from "lucide-react"
import ToolUseBlock from "./ToolUseBlock"
import type { Message } from "../types"

interface MessageBubbleProps {
  message: Message
}

export default function MessageBubble({ message }: MessageBubbleProps) {
  if (message.role === "tool") {
    return <ToolUseBlock message={message} />
  }

  if (message.role === "error") {
    return (
      <div className="px-4 py-2">
        <div className="flex items-start gap-2 rounded-md border border-destructive/50 bg-destructive/10 p-3">
          <AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
          <pre className="whitespace-pre-wrap text-sm text-destructive">
            {message.content}
          </pre>
        </div>
      </div>
    )
  }

  const isUser = message.role === "user"

  return (
    <div
      className={cn("flex px-4 py-2", isUser ? "justify-end" : "justify-start")}
    >
      <div
        className={cn(
          "max-w-[80%] rounded-lg px-4 py-2",
          isUser
            ? "bg-primary text-primary-foreground"
            : "bg-muted text-foreground"
        )}
      >
        <div className="whitespace-pre-wrap text-sm">{message.content}</div>
      </div>
    </div>
  )
}
