import { useEffect, useRef } from "react"
import { ScrollArea } from "@/ui/scroll-area"
import MessageBubble from "./MessageBubble"
import StreamingIndicator from "./StreamingIndicator"
import type { Message } from "../types"

interface MessageListProps {
  messages: Message[]
  streaming: boolean
  status: string
  setupOutput: string[]
}

const SETUP_PHASES: Record<string, string> = {
  spawning: "Spawning runner...",
  cloning: "Cloning repository...",
  setup_script: "Running setup script...",
  spawning_agent: "Starting agent...",
}

export default function MessageList({ messages, streaming, status, setupOutput }: MessageListProps) {
  const bottomRef = useRef<HTMLDivElement>(null)
  const outputEndRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages, streaming])

  useEffect(() => {
    outputEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [setupOutput])

  const setupMessage = SETUP_PHASES[status]
  const showTerminal = status === "setup_script"

  return (
    <ScrollArea className="flex-1">
      <div className="flex flex-col py-4">
        {setupMessage && (
          <div className="flex flex-col items-center gap-3 px-4 py-8">
            <div className="flex items-center gap-3 rounded-lg border bg-muted/50 px-4 py-3">
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
              <span className="text-sm text-muted-foreground">
                {setupMessage}
              </span>
            </div>

            {showTerminal && (
              <div className="w-full max-w-2xl overflow-hidden rounded-lg border border-zinc-800 bg-zinc-950">
                <div className="flex items-center gap-2 border-b border-zinc-800 px-3 py-1.5">
                  <div className="flex gap-1.5">
                    <div className="h-2.5 w-2.5 rounded-full bg-zinc-700" />
                    <div className="h-2.5 w-2.5 rounded-full bg-zinc-700" />
                    <div className="h-2.5 w-2.5 rounded-full bg-zinc-700" />
                  </div>
                  <span className="text-[10px] text-zinc-500">setup script</span>
                </div>
                <div className="max-h-64 overflow-y-auto p-3 font-mono text-xs leading-5 text-zinc-300">
                  {setupOutput.length === 0 ? (
                    <div className="text-zinc-500">Setting up...</div>
                  ) : (
                    setupOutput.map((line, i) => (
                      <div key={i} className="whitespace-pre-wrap break-all">
                        {line || "\u00A0"}
                      </div>
                    ))
                  )}
                  <div ref={outputEndRef} />
                </div>
              </div>
            )}
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
