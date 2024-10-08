plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.8.0"
}
rootProject.name = "helpers-bash-scripts"

include("BashLib")
include("Cloudquery")
include("Docker")
include("GmailFilters")
include("Github")
include("GPT_API_Config")
include("PulaMariana")
include("rclone")
include("ZSH_config_template")
include("GlobalProtectedVPN")
