###############################################################################
# DO NOT EXECUTE THIS FILE
# IT IS INTENDED TO BE INCLUDED WITH THE FOLLOWING SYNTAX:
# source ${0%/*}/common.sh
# (the directory of the calling script is assumed to be the same as common.sh)
###############################################################################

VERSION='1.2.3'

function message() {
    echo
    echo '--------------------------------------------------------------------'
    echo $1
    echo '--------------------------------------------------------------------'
}

function exit_error() {
    echo -e $1
    exit -1
}


function compare_version() {
    if [[ $1 == $2 ]]
    then
        echo 0
        return
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            echo 1
            return
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            echo 2
            return
        fi
    done
    echo 0
}

function device_name() {
    case $1 in
        'linux-rasp-pi-g++') NAME='rpi1' ;;
        'linux-rasp-pi2-g++') NAME='rpi2' ;;
        'linux-rasp-pi3-g++'|'linux-rpi3-g++') NAME='rpi3' ;;
    esac
    echo $NAME
}

function target_device() {
    case $1 in
        'rpi1') DEVICE='linux-rasp-pi-g++' ;;
        'rpi2') DEVICE='linux-rasp-pi2-g++' ;;
        'rpi3')
            if [[ $(compare_version $2 '5.6.2') -lt 2 ]]; then
                DEVICE='linux-rpi3-g++'
            else
                DEVICE='linux-rasp-pi3-g++'                 
            fi
            ;;
    esac
    echo $DEVICE
}

validate_var_qtrpi_qt_version() {
    for VERSION in '5.6.2' '5.9.9' '5.12.7'; do
        if [[ "$QTRPI_QT_VERSION" == "$VERSION" ]]; then
            VALID=true
        fi
    done

    if [[ ! $VALID ]]; then
        exit_error "Invalid QTRPI_QT_VERSION value ($QTRPI_QT_VERSION). Supported values: \n- 5.6.2 \n- 5.9.9 \n- 5.12.7"
    fi
}

validate_var_qtrpi_target_device() {
    NAME=$(target_device $QTRPI_TARGET_DEVICE $QTRPI_QT_VERSION)

    if [[ ! $NAME ]]; then
        exit_error "Invalid QTRPI_TARGET_DEVICE value ($QTRPI_TARGET_DEVICE). Supported values: \n- rpi1 \n- rpi2 \n- rpi3"
    fi
}

validate_var_qtrpi_target_host() {
    TARGET_USER=$(echo $QTRPI_TARGET_HOST | cut -d@ -f1)

    if [[ "$TARGET_USER" == "$QTRPI_TARGET_HOST" ]] ; then
        exit_error "Invalid QTRPI_TARGET_HOST value ($QTRPI_TARGET_HOST). Supported value should have the format 'user@ip-address' (e.g. pi@192.168.0.42)."
    fi
}

check_env_vars() {
    : "${QTRPI_QT_VERSION:?Invalid environment variable, please export QTRPI_QT_VERSION.}"
    : "${QTRPI_TARGET_DEVICE:?Invalid environment variable: please export QTRPI_TARGET_DEVICE.}"
    : "${QTRPI_TARGET_HOST:?Invalid environment variable: please export QTRPI_TARGET_HOST.}"

    validate_var_qtrpi_target_device    
}

ROOT=${QTRPI_ROOT-/opt/qtrpi}
QT_VERSION=${QTRPI_QT_VERSION-'5.12.7'}
DEVICE_NAME=${QTRPI_TARGET_DEVICE-'rpi3'}
TARGET_DEVICE=$(target_device $DEVICE_NAME $QT_VERSION)
TARGET_HOST=$QTRPI_TARGET_HOST
RASPBIAN_BASENAME='raspbian_latest'

QTRPI_TAG="${DEVICE_NAME}_qt-${QT_VERSION}"
QTRPI_ZIP="qtrpi-${QTRPI_TAG}.zip"
QTRPI_BASE_URL='http://www.qtrpi.com/downloads'
QTRPI_SYSROOT_URL="$QTRPI_BASE_URL/sysroot/qtrpi-sysroot-minimal-latest.zip"
QTRPI_MINIMAL_URL="$QTRPI_BASE_URL/qtrpi/$DEVICE_NAME/$QTRPI_ZIP"
QTRPI_CURL_OPT=''

# evaluate docker usage
if [[ $QTRPI_DOCKER ]]; then
    DOCKER_BUILD=$QTRPI_DOCKER
fi

# Get absolute path of script dir for later execution
# /!\ has to be executed *before* any "cd" command
SCRIPT=$( readlink -m $( type -p $0 ))
UTILS_DIR=`dirname ${SCRIPT}`

if [[ "$UTILS_DIR" != *utils ]]; then
    UTILS_DIR="$UTILS_DIR/utils"
fi

if [[ ! $DOCKER_BUILD ]]; then
    # exclude new lines from array
    readarray -t QT_MODULES < $(realpath $UTILS_DIR/../)/qt-modules.txt
    SYSROOT_DEPS_FILE=$(realpath $UTILS_DIR/../)/sysroot-dependencies.txt
    SYSROOT_DEPENDENCIES=$(tr '\n' ' ' < $SYSROOT_DEPS_FILE)
fi

function cd_root() {
    if [[ ! -d $ROOT ]]; then
        exit_error "$ROOT directory does not exist. Please initialize it."
    fi
    cd $ROOT
}

function clean_git_and_compilation() {
    git reset --hard HEAD
    git clean -fd
    make clean -j 10
    make distclean -j 10
}

function qmake_cmd() {
    LOG_FILE=${1:-'default'}
    $ROOT/raspi/qt5/bin/qmake |& tee $ROOT/logs/$LOG_FILE.log
}

function make_cmd() {
    LOG_FILE=${1:-'default'}
    make -j 10 |& tee --append $ROOT/logs/$LOG_FILE.log
}

function download_sysroot_minimal() {
    INSTALL=${1:-true}
    message "Download sysroot-minimal from $QTRPI_SYSROOT_URL"
    SYSROOT_ZIP='sysroot-minimal-latest.zip'
    curl $QTRPI_CURL_OPT -o $SYSROOT_ZIP $QTRPI_SYSROOT_URL
    if [[ "$INSTALL" = true ]]; then
        unzip -o $SYSROOT_ZIP
        $UTILS_DIR/switch-sysroot.sh minimal
    fi
}

function download_qtrpi_binaries() {
    INSTALL=${1:-true}
    message "Download qtrpi binaries from $QTRPI_MINIMAL_URL"
    curl $QTRPI_CURL_OPT -o $QTRPI_ZIP $QTRPI_MINIMAL_URL
    if [[ "$INSTALL" = true ]]; then
        unzip -o $QTRPI_ZIP
        ln -sf $ROOT/raspi/qt5/bin/qmake $ROOT/bin/qmake-qtrpi
    fi
}