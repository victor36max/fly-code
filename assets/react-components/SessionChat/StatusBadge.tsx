import { Badge } from "@/ui/badge"
import { cn } from "../../lib/utils"

interface StatusBadgeProps {
  status: string
  className?: string
}

const statusConfig: Record<string, { variant: "default" | "secondary" | "destructive" | "outline"; label: string; pulse?: boolean; pulseColor?: string }> = {
  spawning: { variant: "outline", label: "Spawning", pulse: true, pulseColor: "bg-blue-400" },
  cloning: { variant: "outline", label: "Cloning", pulse: true, pulseColor: "bg-yellow-400" },
  setup_script: { variant: "outline", label: "Running setup", pulse: true, pulseColor: "bg-yellow-400" },
  spawning_agent: { variant: "outline", label: "Starting agent", pulse: true, pulseColor: "bg-blue-400" },
  active: { variant: "default", label: "Active", pulseColor: "bg-green-400" },
  completed: { variant: "secondary", label: "Completed" },
  shutdown: { variant: "destructive", label: "Shutdown" },
  failed: { variant: "destructive", label: "Failed" },
}

export default function StatusBadge({ status, className }: StatusBadgeProps) {
  const config = statusConfig[status] || { variant: "secondary" as const, label: status }

  return (
    <Badge variant={config.variant} className={cn(className)}>
      {status === "active" && (
        <span className="mr-1.5 inline-block h-2 w-2 animate-pulse rounded-full bg-green-400" />
      )}
      {config.pulse && (
        <span className={cn("mr-1.5 inline-block h-2 w-2 animate-pulse rounded-full", config.pulseColor || "bg-yellow-400")} />
      )}
      {config.label}
    </Badge>
  )
}
