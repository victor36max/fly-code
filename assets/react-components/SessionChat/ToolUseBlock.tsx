import { useState } from "react"
import { ChevronRight, Loader2 } from "lucide-react"
import { Collapsible, CollapsibleTrigger, CollapsibleContent } from "@/ui/collapsible"
import { cn } from "../../lib/utils"
import type { Message } from "../types"

interface ToolUseBlockProps {
  message: Message
}

function getInputSummary(toolName: string, rawInput?: string): string | null {
  if (!rawInput) return null

  try {
    const input = JSON.parse(rawInput)

    switch (toolName) {
      case "Bash":
        return input.command || null
      case "Read":
        return input.file_path || null
      case "Write":
        return input.file_path || null
      case "Edit":
        return input.file_path || null
      case "Grep":
        return input.pattern || null
      case "Glob":
        return input.pattern || null
      case "Agent":
        return input.description || null
      default:
        return rawInput
    }
  } catch {
    return rawInput
  }
}

function formatEditInput(rawInput: string): string | null {
  try {
    const input = JSON.parse(rawInput)
    if (!input.old_string && !input.new_string) return null

    const parts: string[] = []
    if (input.old_string) {
      parts.push(`--- old\n${input.old_string}`)
    }
    if (input.new_string) {
      parts.push(`+++ new\n${input.new_string}`)
    }
    return parts.join("\n")
  } catch {
    return null
  }
}

function getExpandedInput(toolName: string, rawInput?: string): string | null {
  if (!rawInput) return null

  if (toolName === "Edit") {
    return formatEditInput(rawInput)
  }

  // For other tools, show the full input JSON (pretty-printed)
  try {
    const input = JSON.parse(rawInput)
    return JSON.stringify(input, null, 2)
  } catch {
    return rawInput
  }
}

export default function ToolUseBlock({ message }: ToolUseBlockProps) {
  const [open, setOpen] = useState(false)
  const isRunning = message.content === "Running..."
  const inputSummary = getInputSummary(message.tool_name || "tool", message.tool_input)
  const expandedInput = getExpandedInput(message.tool_name || "tool", message.tool_input)

  return (
    <div className="px-4 py-1">
      <Collapsible open={open} onOpenChange={setOpen}>
        <CollapsibleTrigger className="flex items-center gap-2 rounded-md px-2 py-1 text-xs text-muted-foreground transition-colors hover:bg-muted">
          {isRunning ? (
            <Loader2 className="h-3 w-3 animate-spin" />
          ) : (
            <ChevronRight
              className={cn(
                "h-3 w-3 transition-transform",
                open && "rotate-90"
              )}
            />
          )}
          <span className="font-mono font-medium">
            {message.tool_name || "tool"}
          </span>
          {inputSummary && (
            <span className="font-mono text-muted-foreground/70 truncate max-w-md">
              {inputSummary}
            </span>
          )}
        </CollapsibleTrigger>
        {!isRunning && (
          <CollapsibleContent>
            {expandedInput && (
              <pre className="mt-1 overflow-x-auto rounded-md bg-muted/50 p-3 text-xs border-l-2 border-muted-foreground/20">
                <code>{expandedInput}</code>
              </pre>
            )}
            <pre className="mt-1 overflow-x-auto rounded-md bg-muted p-3 text-xs">
              <code>{message.content}</code>
            </pre>
          </CollapsibleContent>
        )}
      </Collapsible>
    </div>
  )
}
