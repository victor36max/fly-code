import { Badge } from "@/ui/badge"
import { cn } from "../../lib/utils"

interface StatusBadgeProps {
  status: string
  className?: string
}

const statusConfig: Record<string, { variant: "default" | "secondary" | "destructive" | "outline"; label: string; pulse?: boolean }> = {
  cloning: { variant: "outline", label: "Cloning", pulse: true },
  active: { variant: "default", label: "Active" },
  idle: { variant: "secondary", label: "Idle" },
  shutdown: { variant: "destructive", label: "Shutdown" },
}

export default function StatusBadge({ status, className }: StatusBadgeProps) {
  const config = statusConfig[status] || { variant: "secondary" as const, label: status }

  return (
    <Badge variant={config.variant} className={cn(className)}>
      {status === "active" && (
        <span className="mr-1.5 inline-block h-2 w-2 animate-pulse rounded-full bg-green-400" />
      )}
      {config.pulse && (
        <span className="mr-1.5 inline-block h-2 w-2 animate-pulse rounded-full bg-yellow-400" />
      )}
      {config.label}
    </Badge>
  )
}
