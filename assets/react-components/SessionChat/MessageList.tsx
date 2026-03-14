import { useEffect, useRef } from "react"
import { ScrollArea } from "@/ui/scroll-area"
import MessageBubble from "./MessageBubble"
import StreamingIndicator from "./StreamingIndicator"
import type { Message } from "../types"

interface MessageListProps {
  messages: Message[]
  streaming: boolean
  status: string
}

export default function MessageList({ messages, streaming, status }: MessageListProps) {
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages, streaming])

  return (
    <ScrollArea className="flex-1">
      <div className="flex flex-col py-4">
        {(status === "cloning" || status === "setup") && (
          <div className="flex items-center justify-center py-8">
            <div className="flex items-center gap-3 rounded-lg border bg-muted/50 px-4 py-3">
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
              <span className="text-sm text-muted-foreground">
                {status === "cloning" ? "Cloning repository..." : "Running setup script..."}
              </span>
            </div>
          </div>
        )}

        {messages.map((message) => (
          <MessageBubble key={message.id} message={message} />
        ))}

        {streaming && <StreamingIndicator />}

        <div ref={bottomRef} />
      </div>
    </ScrollArea>
  )
}
