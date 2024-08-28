import org.gradle.jvm.tasks.Jar

plugins {
    kotlin("jvm") version "2.0.20"
    application
}

group = "app"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}

kotlin {
    jvmToolchain(21)
}

application {
    mainClass.set("app.MainKt")
}

tasks.named<Jar>("jar") {
    manifest {
        attributes["Main-Class"] = "app.MainKt"
    }
}