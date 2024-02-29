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

echo "You will be prompted for your password by sudo."

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

SUDO=sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=''
else
    # Clear any previous sudo permission
    sudo -k
fi

install_torizon_repo () {
    SUITE=$1
    COMPONENT=$2
    $SUDO sh <<SCRIPT
export DEBIAN_FRONTEND=noninteractive
mkdir -p /usr/share/keyrings/  

    apt-get -y update -qq >/dev/null && apt-get install -y -qq curl gpg >/dev/null
    curl -s https://feeds.toradex.com/staging/"${OS}"/toradex-debian-repo-19092023.asc | gpg --dearmor > /usr/share/keyrings/toradex.gpg
    echo "Adding the following package feed:"
    cat > /etc/apt/sources.list.d/toradex.list <<EOF
deb [signed-by=/usr/share/keyrings/toradex.gpg] https://feeds.toradex.com/staging/${OS}/ ${SUITE} ${COMPONENT}
EOF
    cat /etc/apt/sources.list.d/toradex.list
    apt-get -y update -qq >/dev/null
    apt-get -y install -qq aktualizr-torizon >/dev/null
SCRIPT
}

case ${OS} in
    ubuntu|debian)

case ${CODENAME} in
    jammy|focal)
        install_torizon_repo ${CODENAME} main
        ;;

    trixie)
        install_torizon_repo testing main
        ;;

    bookworm)
        install_torizon_repo stable main
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

curl -fsSL https://app.torizon.io/statics/scripts/provision-device.sh | bash -s -- -u https://app.torizon.io/api/accounts/devices -t "${access}" && systemctl restart aktualizr
echo "Your device is provisioned! ⭐"
