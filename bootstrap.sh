#!/usr/bin/env bash

# PostgreSQL version.
PG_VERSION=9.4

# Database security and name settings.
APP_DB_USER=sonarqube
APP_DB_PASS=sonarqube
APP_DB_NAME=${APP_DB_USER}

# SonarQube version.
SONARQUBE_VERSION=6.7.1

export DEBIAN_FRONTEND=noninteractive

PROVISIONED_ON=/etc/vm_provision_on_timestamp
if [ -f "$PROVISIONED_ON" ]
then
  echo "VM was already provisioned at: $(cat ${PROVISIONED_ON})"
fi

PG_REPO_APT_SOURCE=/etc/apt/sources.list.d/pgdg.list
if [ ! -f "$PG_REPO_APT_SOURCE" ]
then
  # Add PG apt repo.
  echo "deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main" > "$PG_REPO_APT_SOURCE"

  # Add PGDG repo key.
  wget --quiet -O - https://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | apt-key add -
fi

# Update package list and upgrade all packages.
add-apt-repository -y ppa:openjdk-r/ppa
apt-get update
apt-get -y upgrade

# Setup Java and other useful tools.
apt-get -y install openjdk-8-jdk
apt-get -y install unzip

# Setup PostgreSQL.
apt-get -y install "postgresql-$PG_VERSION" "postgresql-contrib-$PG_VERSION"

PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
PG_DIR="/var/lib/postgresql/$PG_VERSION/main"

# Edit postgresql.conf to change listen address to '*'.
sed -i 's/#listen_addresses = 'localhost'/listen_addresses = '*'/' ${PG_CONF}

# Append to pg_hba.conf to add password auth.
echo 'host    all             all             all                     md5' >> ${PG_HBA}

# Explicitly set default client_encoding.
echo "client_encoding = utf8" >> "$PG_CONF"

# Restart so that all new configs are loaded.
service postgresql restart

cat << EOF | su - postgres -c psql
CREATE USER ${APP_DB_USER} WITH PASSWORD '${APP_DB_PASS}';

CREATE DATABASE ${APP_DB_NAME} WITH OWNER=${APP_DB_USER}
LC_COLLATE='en_US.utf8'
LC_CTYPE='en_US.utf8'
ENCODING='UTF8'
TEMPLATE=template0;
EOF

# Download sonarqube.
url="https://sonarsource.bintray.com/Distribution/sonarqube/sonarqube-$SONARQUBE_VERSION.zip"
wget --quiet ${url}

# Unzip and move files to /opt dir.
sonarqube="sonarqube-$SONARQUBE_VERSION"

unzip "$sonarqube.zip"
rm "$sonarqube.zip"
mv ${sonarqube} "/opt/$sonarqube"

# Setup config.
sonarqube="/opt/$sonarqube"

cat <<EOT >> "${sonarqube}/conf/sonar.properties"
sonar.jdbc.username=${APP_DB_USER}
sonar.jdbc.password=${APP_DB_PASS}
sonar.jdbc.url=jdbc:postgresql://localhost/${APP_DB_USER}
EOT

# Setup sonar user.
groupadd sonar
useradd -c "SonarQube System User" -d ${sonarqube} -g sonar -s /bin/bash sonar
chown -R sonar:sonar ${sonarqube}

sonarExec="${sonarqube}/bin/linux-x86-64/sonar.sh"
echo -e "RUN_AS_USER=sonar\n$(cat ${sonarExec})" > ${sonarExec}

# Start sonarqube.
${sonarExec} start

# Tag the provision time.
date > "$PROVISIONED_ON"