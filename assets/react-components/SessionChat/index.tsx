import { Link } from "live_react"
import { useLiveReact } from "live_react"
import { ArrowLeft, Check, ChevronDown, Eye, Hammer, Square } from "lucide-react"
import { Button } from "@/ui/button"
import { Badge } from "@/ui/badge"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/ui/dropdown-menu"
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
  setup_output: string[]
  current_model: string
  current_mode: string
  available_models: Array<{ id: string; name: string }>
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
  setup_output,
  current_model,
  current_mode,
  available_models,
}: SessionChatProps) {
  const { pushEvent } = useLiveReact()

  const projectName = db_session?.project?.name
  const inputDisabled = streaming || status !== "active"

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
        setupOutput={setup_output}
      />

      <div className="flex items-center gap-2 border-t px-4 py-2">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="sm" disabled={status !== "active"}>
              {available_models.find((m) => m.id === current_model)?.name ??
                current_model}
              <ChevronDown className="ml-1 h-3 w-3" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent>
            {available_models.map((model) => (
              <DropdownMenuItem
                key={model.id}
                onClick={() => pushEvent("set_model", { model: model.id })}
              >
                {model.name}
                {model.id === current_model && (
                  <Check className="ml-auto h-3 w-3" />
                )}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>

        <Button
          variant={current_mode === "plan" ? "secondary" : "outline"}
          size="sm"
          onClick={() =>
            pushEvent("set_mode", {
              mode: current_mode === "plan" ? "build" : "plan",
            })
          }
          disabled={status !== "active"}
        >
          {current_mode === "plan" ? (
            <Eye className="mr-1 h-3 w-3" />
          ) : (
            <Hammer className="mr-1 h-3 w-3" />
          )}
          {current_mode === "plan" ? "Plan" : "Build"}
        </Button>

        <div className="flex-1" />

        {streaming && (
          <Button
            variant="destructive"
            size="sm"
            onClick={() => pushEvent("interrupt", {})}
          >
            <Square className="mr-1 h-3 w-3" />
            Stop
          </Button>
        )}
      </div>

      <ChatInput
        inputText={input_text}
        disabled={inputDisabled}
        onSend={(text) => pushEvent("send_message", { text })}
        onUpdateInput={(text) => pushEvent("update_input", { text })}
      />
    </div>
  )
}
