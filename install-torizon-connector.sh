#!/usr/bin/env bash
set -e

[ -n "${DO_NOT_PROVISION:-}" ] && set -x

LOGFILE=/tmp/install-torizon-plugin.log

trap '
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: script failed with exit code $rc"
    if [ -f "'"$LOGFILE"'" ]; then
      cat "'"$LOGFILE"'"
    else
      echo "No log file found at '"$LOGFILE"'"
    fi
  fi
' EXIT

echo "======================================================"
echo " Torizon Connector for apt-based distributions "
echo "======================================================"
echo '                                                    '
echo '                      ******,                       '      
echo '                   ************                     '      
echo '              *****    ****,     ***                '      
echo '          ************,      .**********            '      
echo '      **     *******          *********             '      
echo '  .*********          ((((((((    *.     *******    '      
echo '  **********        /(((((((((((      ************* '      
echo '      **.     *****.    ((((      ****    *****     '      
echo '           ************       ************          '      
echo ' %%%          ******      *     ********       &%%% '      
echo '  *%%%%%              *********             %%%%%   '      
echo '      %%%%%%         ***********        %%%%%     . '      
echo ' ***      %%%%%&         ***        %%%%%.     **** '      
echo '   *****      %%%%%.            %%%%%%     ******   '      
echo '      .*****      %%%%%     %%%%%%      *****       '      
echo '          ******     .%%%%%%%%      *****           '      
echo '              ******            *****               '      
echo '                  *****     ******                  '      
echo '                      ********                      '      
echo '                                                    '      


YELLOW='\033[0;33m'
NC='\033[0m' # No Color

check_if_already_provisioned () {
  if [ -f /var/sota/import/info.json ]; then
      read -rp "Device already provisioned! Do you want to reprovision it? [y/N]" reprovision
      if [ -z "$reprovision" ] || [ "$reprovision" = "N" ] || [ "$reprovision" = "n" ]; then
        exit 0
      elif [ "$reprovision" = "Y" ] || [ "$reprovision" = "y" ]; then
        :
      else
        check_if_already_provisioned
      fi
  fi
}

check_if_install () {
  read -rp "Do you want to continue? [Y/n]" install
  if [ -z "$install" ] || [ "$install" = "Y" ] || [ "$install" = "y" ]; then
    :
  elif [ "$install" = "N" ] || [ "$install" = "n" ]; then
    exit 0
  else
    check_if_install
  fi
}

# Determine package type to install: https://unix.stackexchange.com/a/6348
# OS used by all - for Debs it must be Ubuntu or Debian
# CODENAME only used for Debs
if [ -f /etc/os-release ]; then
    # Debian uses Dash which does not support source
    # shellcheck source=/dev/null
    . /etc/os-release
    OS=$( echo "${ID}" | tr '[:upper:]' '[:lower:]')
    CODENAME=$( echo "${VERSION_CODENAME}" | tr '[:upper:]' '[:lower:]')
elif lsb_release &>/dev/null; then
    OS=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    CODENAME=$(lsb_release -cs)
else
    OS=$(uname -s)
fi

ARCH=$(dpkg --print-architecture)

if [ "$(id -u)" != "0" ]; then
    echo "This script should execute as root. Use sudo or run from root user."
    exit 1
fi

if command -v docker >/dev/null 2>&1; then
    DOCKER_ALREADY_INSTALLED=1
    echo "Docker detected on system, will not add Docker APT repository or reinstall Docker packages."
else
    DOCKER_ALREADY_INSTALLED=0
    echo "Docker not detected, Docker packages and repository will be installed."
fi

install_torizon_repo () {
    CODENAME=$1
    COMPONENT=$2

    echo "Installation has started, it may take a few minutes."

    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /usr/share/keyrings/

    echo "Installing curl and gpg" > "$LOGFILE"
    apt-get -y update -qq >> "$LOGFILE" 2>&1 && apt-get install -y -qq curl gpg >>"$LOGFILE" 2>&1

    curl -fsSL https://feeds.toradex.com/torizon/connector/toradex-debian-repo-07102024.asc | gpg --dearmor > /usr/share/keyrings/toradex.gpg
    curl -fsSL https://packages.fluentbit.io/fluentbit.key | gpg --dearmor > /usr/share/keyrings/fluentbit-keyring.gpg

    # Only add Docker key if Docker is not already installed
    if [ "$DOCKER_ALREADY_INSTALLED" -eq 0 ]; then
        curl -fsSL "https://download.docker.com/linux/${OS}/gpg" | gpg --dearmor > /usr/share/keyrings/docker.gpg
    fi

    # Always add Toradex and Fluent Bit feeds
    cat > /etc/apt/sources.list.d/toradex.list <<EOF
deb [signed-by=/usr/share/keyrings/toradex.gpg] https://feeds.toradex.com/torizon/connector/${OS}/${CODENAME} ${CODENAME} ${COMPONENT}
deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/${OS}/${CODENAME} ${CODENAME} main
EOF

    # Only add Docker repo if Docker is not already installed
    if [ "$DOCKER_ALREADY_INSTALLED" -eq 0 ]; then
cat >> /etc/apt/sources.list.d/toradex.list <<EOF
deb [signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/${OS} ${CODENAME} stable
EOF
    fi

    echo "Adding the following package feeds:" >> "$LOGFILE"
    cat /etc/apt/sources.list.d/toradex.list >> "$LOGFILE"

    echo "Installing dependencies (${PKGS_TO_INSTALL})" >> "$LOGFILE"
    apt-get -y update -qq >> "$LOGFILE" 2>&1
    apt-get -y install -qq ${PKGS_TO_INSTALL} >> "$LOGFILE" 2>&1

    if [ ! -f /usr/bin/docker-compose ]; then
      cat > /usr/bin/docker-compose <<EOF
#!/bin/sh
# make docker-compose an "alias" do docker compose

docker compose \$@
EOF
      chmod a+x /usr/bin/docker-compose
      echo "Adding /usr/bin/docker-compose:" >> "$LOGFILE"
      cat /usr/bin/docker-compose >> "$LOGFILE"
    fi

    if [ ! -f /etc/systemd/system/docker-compose.service ]; then
      if [ -n "${DO_NOT_PROVISION:-}" ]; then
        echo "DO_NOT_PROVISION set, skipping docker-compose.service installation" >> "$LOGFILE"
      elif [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        cat > /etc/systemd/system/docker-compose.service <<EOF
[Unit]
Description=Docker Compose service with docker compose
Requires=docker.service
After=docker.service
ConditionPathExists=/var/sota/storage/docker-compose/docker-compose.yml
ConditionPathExists=!/var/sota/storage/docker-compose/docker-compose.yml.tmp
OnFailure=docker-integrity-checker.service

[Service]
Type=simple
WorkingDirectory=/var/sota/storage/docker-compose/
ExecStart=/usr/bin/docker-compose -p torizon up -d --remove-orphans
ExecStartPost=rm -f /tmp/recovery-attempt.txt
ExecStop=/usr/bin/docker-compose -p torizon down
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable docker-compose >> "$LOGFILE" 2>&1
        echo "Adding /etc/systemd/system/docker-compose.service:" >> "$LOGFILE"
        cat /etc/systemd/system/docker-compose.service >> "$LOGFILE"
      else
        echo "systemd not detected, skipping docker-compose.service installation" >> "$LOGFILE"
      fi
    fi

    if [ -f /etc/fluent-bit/fluent-bit.conf ]; then
        rm -f /etc/fluent-bit/fluent-bit.conf
        cat > /etc/fluent-bit/fluent-bit.conf <<EOF
[SERVICE]
    flush        1
    daemon       Off
    log_level    info
    parsers_file parsers.conf
    plugins_file plugins.conf

[INPUT]
    name          cpu
    tag           cpu
    interval_sec  300
    Mem_Buf_Limit 5MB

[FILTER]
    Name       nest
    Match      cpu
    Operation  nest
    Wildcard   *
    Nest_under cpu

[INPUT]
    name          mem
    tag           memory
    interval_sec  300
    Mem_Buf_Limit 5MB

[FILTER]
    Name       nest
    Match      memory
    Operation  nest
    Wildcard   *
    Nest_under memory

[INPUT]
    name          thermal
    tag           temperature
    name_regex    thermal_zone0
    interval_sec  300
    Mem_Buf_Limit 5MB

[FILTER]
    Name       nest
    Match      temperature
    Operation  nest
    Wildcard   *
    Nest_under temperature

[INPUT]
    name          proc
    proc_name     dockerd
    tag           proc_docker
    fd            false
    mem           false
    interval_sec  300
    Mem_Buf_Limit 5MB

[FILTER]
    Name       nest
    Match      proc_docker
    Operation  nest
    Wildcard   *
    Nest_under docker

[INPUT]
    Name          exec
    Tag           emmc_health
    Command       /usr/bin/emmc-health
    Parser        json
    Interval_Sec  300
    Mem_Buf_Limit 5MB

[FILTER]
    Name       nest
    Match      emmc_health
    Operation  nest
    Wildcard   *
    Nest_under custom

[OUTPUT]
    name         http
    match        *
    host         dgw.torizon.io
    port         443
    uri          monitoring/fluentbit-metrics
    format       json
    tls          on
    tls.verify   off
    tls.ca_file  /etc/sota/root.crt
    tls.key_file /var/sota/import/pkey.pem
    tls.crt_file /var/sota/import/client.pem
    Retry_Limit  10
EOF
        echo "Adding /etc/fluent-bit/fluent-bit.conf:" >> "$LOGFILE"
        cat /etc/fluent-bit/fluent-bit.conf >> "$LOGFILE"
    fi

    # gecos option has changed to comment in bookworm or newer
    case $CODENAME in
        noble|bookworm)
            adduser_gecos_opt="--comment"
            ;;
        *)
            adduser_gecos_opt="--gecos"
            ;;
    esac

    if [ -z "$(id -u torizon 2>> "$LOGFILE")" ]; then
        echo "Now we have to create the torizon user so remote access works out of the box. Please, fill in the password for torizon user."
        adduser ${adduser_gecos_opt} '' torizon
    fi
    adduser torizon sudo >> "$LOGFILE" 2>&1
    adduser torizon docker >> "$LOGFILE" 2>&1
}

check_if_already_provisioned

echo "This script will:
  - Add Toradex's and Fluent Bit's package feeds to your system (and Docker's feed if Docker is not already installed);
  - Create a docker-compose binary at /usr/bin;
  - Install a docker-compose systemd service;
  - Create torizon user and add it to sudo and docker groups;
  - Attempt to provision the device on Torizon Cloud using a pair code;
  - Create a log file in "$LOGFILE"."

# Skip interactive prompt
if [ -z "${DO_NOT_PROVISION:-}" ]; then
    check_if_install
fi

DOCKER_PKGS="containerd.io docker-ce docker-ce-cli docker-compose-plugin"

case ${ARCH} in
    amd64|arm64)
        PKGS_TO_INSTALL="aktualizr-torizon rac fluent-bit sudo"
        if [ "$DOCKER_ALREADY_INSTALLED" -eq 0 ]; then
            PKGS_TO_INSTALL="$PKGS_TO_INSTALL $DOCKER_PKGS"
        fi
        ;;

    *)
        echo "${ARCH} is currently not supported. Get in touch with us at community.toradex.com for more information."
        exit 1
        ;;
esac

case ${OS} in
    ubuntu|debian)

        case ${CODENAME} in
            noble|jammy)
                install_torizon_repo "${CODENAME}" main
                ;;

            bookworm|trixie)
                install_torizon_repo "${CODENAME}" main
                ;;

            *)
                echo "Unsupported release: ${CODENAME} for ${OS}."
                exit 1
                ;;
        esac

        ;;

    *)
        echo "${OS} not supported."
        exit 1
        ;;
esac

echo "Installation of dependencies completed!"

# Early exit for CI after dependency check
if [ -n "${DO_NOT_PROVISION:-}" ]; then
    aktualizr-torizon --version
    rac --version
    exit 0
fi

echo "Retrieving one-time pairing token"
echo "Ready to pair..."

response=$(curl -fsSL "https://app.torizon.io/api/provision-code")
code=$(echo "$response" | awk -F'"' '/provisionCode/{print $4}')
uuid=$(echo "$response" | awk -F'"' '/provisionUuid/{print $8}')

echo "👉 Go to https://pair.torizon.io and use code ${YELLOW}$code ${NC}to provision your device"
echo "This script will terminate automatically after the pairing process is finished!"

while true; do
    sleep 10

    provision_info=$(curl -fsSL "https://app.torizon.io/api/provision-code?provisionUuid=$uuid")
    access=$(echo "$provision_info" | awk -F'"' '/access/{print $4}')
    if [ "$access" != "" ]; then
        break
    fi
done

sh <<SCRIPT
curl -fsSL https://app.torizon.io/statics/scripts/provision-device.sh | bash -s -- -u https://app.torizon.io/api/accounts/devices -t "${access}" && systemctl restart aktualizr rac
SCRIPT

echo "Your device is provisioned! ⭐"
