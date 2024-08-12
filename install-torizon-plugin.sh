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

SUDO=sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=''
else
    echo "You will be prompted for your password by sudo."
    # Clear any previous sudo permission
    sudo -k
fi

install_torizon_repo () {
    SUITE=$1
    COMPONENT=$2

    echo "Installation has started, it may take a few minutes."

    $SUDO sh <<SCRIPT
export DEBIAN_FRONTEND=noninteractive
mkdir -p /usr/share/keyrings/

    apt-get -y update -qq >/dev/null && apt-get install -y -qq curl gpg >/dev/null
    curl -s https://feeds.toradex.com/staging/"${OS}"/toradex-debian-repo-19092023.asc | gpg --dearmor > /usr/share/keyrings/toradex.gpg
    curl https://packages.fluentbit.io/fluentbit.key | gpg --dearmor > /usr/share/keyrings/fluentbit-keyring.gpg
    echo "Adding the following package feeds:"
    cat > /etc/apt/sources.list.d/toradex.list <<EOF
deb [signed-by=/usr/share/keyrings/toradex.gpg] https://feeds.toradex.com/staging/${OS}/ ${SUITE} ${COMPONENT}
deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/${OS}/${CODENAME} ${CODENAME} main
EOF

    cat /etc/apt/sources.list.d/toradex.list
    apt-get -y update -qq >/dev/null
    apt-get -y install -qq ${PKGS_TO_INSTALL} >/dev/null

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
SCRIPT
}

case ${ARCH} in
    amd64|arm64)
        PKGS_TO_INSTALL="aktualizr-torizon fluent-bit rac"
        ;;

    armhf)
        PKGS_TO_INSTALL="aktualizr-torizon rac"
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

$SUDO sh <<SCRIPT
curl -fsSL https://app.torizon.io/statics/scripts/provision-device.sh | bash -s -- -u https://app.torizon.io/api/accounts/devices -t "${access}" && systemctl restart aktualizr
SCRIPT

echo "Your device is provisioned! ⭐"
