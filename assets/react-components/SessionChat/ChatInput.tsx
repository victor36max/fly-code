import { useState, useRef, useCallback } from "react"
import { Send } from "lucide-react"
import { Button } from "@/ui/button"
import { Textarea } from "@/ui/textarea"

interface ChatInputProps {
  inputText: string
  disabled: boolean
  onSend: (text: string) => void
  onUpdateInput: (text: string) => void
}

export default function ChatInput({
  inputText,
  disabled,
  onSend,
  onUpdateInput,
}: ChatInputProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const [localText, setLocalText] = useState(inputText)

  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setLocalText(e.target.value)
    onUpdateInput(e.target.value)
  }

  const handleSubmit = useCallback(
    (e?: React.FormEvent) => {
      e?.preventDefault()
      const text = localText.trim()
      if (!text || disabled) return
      onSend(text)
      setLocalText("")
    },
    [localText, disabled, onSend]
  )

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      handleSubmit()
    }
  }

  return (
    <form onSubmit={handleSubmit} className="border-t p-4">
      <div className="flex items-end gap-2">
        <Textarea
          ref={textareaRef}
          value={localText}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          placeholder={disabled ? "Waiting..." : "Send a message... (Enter to send, Shift+Enter for newline)"}
          disabled={disabled}
          rows={1}
          className="min-h-[40px] max-h-[160px] resize-none"
        />
        <Button
          type="submit"
          size="icon"
          disabled={disabled || !localText.trim()}
        >
          <Send className="h-4 w-4" />
        </Button>
      </div>
    </form>
  )
}
