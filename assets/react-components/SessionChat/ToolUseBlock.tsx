import { useState } from "react"
import { ChevronRight } from "lucide-react"
import { Collapsible, CollapsibleTrigger, CollapsibleContent } from "@/ui/collapsible"
import { cn } from "../../lib/utils"
import type { Message } from "../types"

interface ToolUseBlockProps {
  message: Message
}

export default function ToolUseBlock({ message }: ToolUseBlockProps) {
  const [open, setOpen] = useState(false)

  return (
    <div className="px-4 py-1">
      <Collapsible open={open} onOpenChange={setOpen}>
        <CollapsibleTrigger className="flex items-center gap-2 rounded-md px-2 py-1 text-xs text-muted-foreground transition-colors hover:bg-muted">
          <ChevronRight
            className={cn(
              "h-3 w-3 transition-transform",
              open && "rotate-90"
            )}
          />
          <span className="font-mono font-medium">
            {message.tool_name || "tool"}
          </span>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <pre className="mt-1 overflow-x-auto rounded-md bg-muted p-3 text-xs">
            <code>{message.content}</code>
          </pre>
        </CollapsibleContent>
      </Collapsible>
    </div>
  )
}
