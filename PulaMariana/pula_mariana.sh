#!/bin/bash
# shellcheck disable=SC2086

export JAVA_21="/home/fernandoavanzo/.jdks/corretto-21.0.4/bin/java"
export GRADLE_JETBRAINS_MODULES="/home/fernandoavanzo/.gradle/caches/modules-2/files-2.1"
export PROJECTS="$HOME/Projects"
export BASH_SCRIPTS="$PROJECTS/helpers-bash-scripts"
export MARIANA="$BASH_SCRIPTS/PulaMariana"
export IDEA_RT="/home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/lib/idea_rt.jar=40653"
export ULTIMATE_BIN="/home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/bin"
export JAVA_AGENT="$IDEA_RT:$ULTIMATE_BIN"
export LOCAL_CLASSPATH="$MARIANA/build/classes/kotlin/main"
export KOTLIN_STD_LIB="$GRADLE_JETBRAINS_MODULES/org.jetbrains.kotlin/kotlin-stdlib/2.0.20/7388d355f7cceb002cd387ccb7ab3850e4e0a07f/kotlin-stdlib-2.0.20.jar"
export ANNOTATIONS="$GRADLE_JETBRAINS_MODULES/org.jetbrains/annotations/13.0/919f0dfe192fb4e063e7dacadee7f8bb9a2672a9/annotations-13.0.jar"
export MARIANA_JUMP="-javaagent:${JAVA_AGENT} -Dfile.encoding=UTF-8 -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8 -classpath ${LOCAL_CLASSPATH}:${KOTLIN_STD_LIB}:${ANNOTATIONS} MainKt"


"$BASH_SCRIPTS"/gradlew clean
"$BASH_SCRIPTS"/gradlew build
$JAVA_21 $MARIANA_JUMP