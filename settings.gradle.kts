pluginManagement {
    plugins {
        kotlin("jvm") version "2.3.20"
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
rootProject.name = "MyCli"

include("BashLib")
include("Cloudquery")
include("Docker")
include("Docker:wiremockCompose")
include("GmailFilters")
include("Github")
include("GPT_API_Config")
include("PulaMariana")
include("rclone")
include("ZSH_config_template")
include("GlobalProtectedVPN")
include("MicrosoftDefenderLinux")
include("Node")
include("Node:Playwright-template")
include("MyCompanys")
include("Linux")
include("1Password")
include("ZscalerVPN")
include("Kubernetes")
include("OpenAPI")
include("OpenAPI:Codex")
include("Ollama-LLMs_Models")
include("Maths")
include("Maths:MonteCarloApp")
include("Maths:F1DownForceSimullator")
include("Maths:DirectEnergyConversionStudy")
include("SamsungGalaxyNote")
include("SamsungGalaxyNote:samsung-galaxy-book-linux-fixes-main")
include("Azure")
include("Unity")
