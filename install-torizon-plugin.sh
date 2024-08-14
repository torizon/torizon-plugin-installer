#!/usr/bin/env bash
set -e

echo "======================================================"
echo " Torizon Plugin Installer for apt-based distributions "
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

install_torizon_repo () {
    SUITE=$1
    COMPONENT=$2

    echo "Installation has started, it may take a few minutes."

export DEBIAN_FRONTEND=noninteractive
mkdir -p /usr/share/keyrings/

    apt-get -y update -qq >/dev/null && apt-get install -y -qq curl gpg >/dev/null

    curl -fsSL https://feeds.toradex.com/staging/"${OS}"/toradex-debian-repo-19092023.asc | gpg --dearmor > /usr/share/keyrings/toradex.gpg
    curl -fsSL https://packages.fluentbit.io/fluentbit.key | gpg --dearmor > /usr/share/keyrings/fluentbit-keyring.gpg
    curl -fsSL "https://download.docker.com/linux/${OS}/gpg" | gpg --dearmor > /usr/share/keyrings/docker.gpg

    echo "Adding the following package feeds:"
    cat > /etc/apt/sources.list.d/toradex.list <<EOF
deb [signed-by=/usr/share/keyrings/toradex.gpg] https://feeds.toradex.com/staging/${OS}/ ${SUITE} ${COMPONENT}
deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/${OS}/${CODENAME} ${CODENAME} main
deb [signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/${OS} ${CODENAME} stable
EOF

    cat /etc/apt/sources.list.d/toradex.list
    apt-get -y update -qq >/dev/null
    apt-get -y install -qq ${PKGS_TO_INSTALL} >/dev/null

    if [ ! -f /usr/bin/docker-compose ]; then
      cat > /usr/bin/docker-compose <<EOF
#!/bin/sh
# make docker-compose an "alias" do docker compose

docker compose \$@
EOF
    chmod a+x /usr/bin/docker-compose
    fi

    if [ ! -f /etc/systemd/system/docker-compose.service ]; then
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
    systemctl enable docker-compose
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

    if [ -z "$(id -u torizon)" ]; then
        echo "Now we have to create the torizon user so remote access works out of the box. Please, fill in the password for torizon user."
        adduser ${adduser_gecos_opt} '' torizon
    fi
    adduser torizon sudo
    adduser torizon docker
}

check_if_already_provisioned

echo "This script will:
  - Add Toradex's, Fluent Bit's and Docker's package feed to your system;
  - Install fluent-bit, docker, aktualizr and rac (remote access client) applications;
  - Create a docker-compose binary at /usr/bin;
  - Install a docker-compose systemd service;
  - Create torizon user and add it to sudo and docker groups;
  - Attempt to provision the device on Torizon Cloud using a pair code."

check_if_install

case ${ARCH} in
    amd64|arm64)
        PKGS_TO_INSTALL="aktualizr-torizon containerd.io docker-ce docker-ce-cli docker-compose-plugin fluent-bit rac sudo"
        ;;

    armhf)
        PKGS_TO_INSTALL="aktualizr-torizon containerd.io docker-ce docker-ce-cli docker-compose-plugin rac sudo"
        ;;

    *)
        echo "${ARCH} not supported."
        exit 1
        ;;
esac

case ${OS} in
    ubuntu|debian)

        case ${CODENAME} in
            noble|jammy|focal)
                install_torizon_repo "${CODENAME}" main
                ;;

            bookworm)
                install_torizon_repo stable main
                ;;

            bullseye)
                install_torizon_repo oldstable main
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

echo "Installation of Aktualizr completed!"

# Early exit for CI
if [ -n "$DO_NOT_PROVISION" ]; then
    # set -e is set, will exit on error
    aktualizr-torizon --version
    exit 0
fi
echo "Ready to pair..."
echo "Retrieving one-time pairing token"

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
curl -fsSL https://app.torizon.io/statics/scripts/provision-device.sh | bash -s -- -u https://app.torizon.io/api/accounts/devices -t "${access}" && systemctl restart aktualizr remote-access
SCRIPT

echo "Your device is provisioned! ⭐"
