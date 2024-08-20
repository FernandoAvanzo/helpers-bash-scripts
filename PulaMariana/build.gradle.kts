import org.gradle.jvm.tasks.Jar

plugins {
    kotlin("jvm") version "2.0.0"
}

group = "org.example"
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

// Configure the existing jar task to include the main class in the manifest
tasks.named<Jar>("jar") {
    manifest {
        attributes["Main-Class"] = "MainKt"
    }
}