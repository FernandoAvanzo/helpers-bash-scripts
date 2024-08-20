#!/bin/bash

export PROJECTS="$HOME/Projects"
export MARIANA="$PROJECTS/helpers-bash-scripts/PulaMariana"


"$MARIANA"/gradlew clean
"$MARIANA"/gradlew build
java \
-javaagent:/home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/lib/idea_rt.jar=38937:/home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/bin \
-Dfile.encoding=UTF-8 \
-Dsun.stdout.encoding=UTF-8 \
-Dsun.stderr.encoding=UTF-8 \
-classpath \
/home/fernandoavanzo/Projects/helpers-bash-scripts/PulaMariana/build/classes/kotlin/main:/home/fernandoavanzo/.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib/2.0.0/b48df2c4aede9586cc931ead433bc02d6fd7879e/kotlin-stdlib-2.0.0.jar:/home/fernandoavanzo/.gradle/caches/modules-2/files-2.1/org.jetbrains/annotations/13.0/919f0dfe192fb4e063e7dacadee7f8bb9a2672a9/annotations-13.0.jar \
MainKt