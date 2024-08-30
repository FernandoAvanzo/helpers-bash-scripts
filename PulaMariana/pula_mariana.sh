#!/bin/bash
# shellcheck disable=SC2086

export GRADLE_JETBRAINS_MODULES="/home/fernandoavanzo/.gradle/caches/modules-2/files-2.1"
export PROJECTS="$HOME/Projects"
export BASH_SCRIPTS="$PROJECTS/helpers-bash-scripts"
export MARIANA="$BASH_SCRIPTS/PulaMariana"

"$BASH_SCRIPTS"/gradlew clean
"$BASH_SCRIPTS"/gradlew build
#$JAVA_21 $MARIANA_JUMP
java -jar $MARIANA/build/libs/PulaMariana-1.0-SNAPSHOT.jar