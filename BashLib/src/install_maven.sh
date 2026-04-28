#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

apt update
apt install -y default-jdk

if [[ -n "${MAVEN_VERSION:-}" ]]; then
  echo "Installing Apache Maven version ${MAVEN_VERSION} manually..."
  cd /tmp
  # Correct URL: uses the full version (e.g. 3.9.15) after maven-3/:contentReference[oaicite:1]{index=1}.
  archive_url="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
  archive_name="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
  if ! wget -q "${archive_url}" -O "${archive_name}"; then
    echo "Error: failed to download Maven archive from ${archive_url}" >&2
    exit 2
  fi
  tar xf "${archive_name}" -C /opt
  ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
  cat >/etc/profile.d/maven.sh <<'EOF'
export JAVA_HOME=/usr/lib/jvm/default-java
export M2_HOME=/opt/maven
export MAVEN_HOME=/opt/maven
export PATH="${M2_HOME}/bin:${PATH}"
EOF
  chmod +x /etc/profile.d/maven.sh
  source /etc/profile.d/maven.sh
else
  echo "Installing Apache Maven from the Pop!_OS/Ubuntu repository..."
  apt install -y maven
fi

mvn -version
