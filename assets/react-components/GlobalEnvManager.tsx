import EnvVarManager from "./EnvVarManager"
import type { EnvVar } from "./types"

interface GlobalEnvManagerProps {
  env_vars: EnvVar[]
  revealed: number[]
  new_key: string
  new_value: string
}

export default function GlobalEnvManager(props: GlobalEnvManagerProps) {
  return (
    <div>
      <div className="mx-auto max-w-3xl px-6 pt-6">
        <p className="text-sm text-muted-foreground">
          Global variables are available to all projects. Project-level variables
          with the same key will override these.
        </p>
      </div>
      <EnvVarManager
        project={null}
        scope="global"
        env_vars={props.env_vars}
        revealed={props.revealed}
        new_key={props.new_key}
        new_value={props.new_value}
      />
    </div>
  )
}
