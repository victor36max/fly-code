// Component registry — live_react looks up components by name from this export
import Toaster from "./Toaster"
import HomeDashboard from "./HomeDashboard"
import ProjectNew from "./ProjectNew"
import ProjectShow from "./ProjectShow"
import EnvVarManager from "./EnvVarManager"
import GlobalEnvManager from "./GlobalEnvManager"
import SessionChat from "./SessionChat"

const components = {
  Toaster,
  HomeDashboard,
  ProjectNew,
  ProjectShow,
  EnvVarManager,
  GlobalEnvManager,
  SessionChat,
}

export default components
