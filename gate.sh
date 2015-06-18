#!/bin/bash -x

# 1. Populate your IRONIC_HWINFO_FILE with the machines of localrc
# 2. Put proxy variables in /proxy
# Invocation:
#
#   export ILO_HWINFO=
#
#   ./gate.sh <driver> <bios|uefi> <hardware details>


set -eu
set -o pipefail

source /proxy

export PATH=$PATH:/var/lib/gems/1.8/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games
export DIB_DEPLOY_ISO_KERNEL_CMDLINE_ARGS="console=ttyS1"
DISTRO=ubuntu

function update_proliantutils {
    if [[ -d /opt/stack/proliantutils ]]; then
        cd /opt/stack/proliantutils
        git fetch origin
        git reset --hard origin/master
    else
        git clone https://github.com/stackforge/proliantutils
    fi
    git log -1
    sudo -E pip install /opt/stack/proliantutils
}

function stop_console {
    PID=$(pidof sshpass || true)
    if [[ -n "$PID" ]]; then
        STOP=$(kill $PID)
    fi
}

function run_stack {
    export IRONIC_DEPLOY_IMAGE_PREFERRED_DISTRO=$DISTRO

    rm -rf /opt/stack/logs
    mkdir -p /opt/stack/logs

    echo -e "$ILO_HWINFO" > /opt/stack/logs/hwinfo
    export ILO_HWINFO_FILE=/opt/stack/logs/hwinfo

    cp /opt/stack/devstack/localrc /opt/stack/logs
    cd /opt/stack/devstack
    ./unstack.sh
    rm -rf /opt/stack/data/*
    ./stack.sh

    source /opt/stack/devstack/openrc admin admin
    IRONIC_NODE=$(ironic node-list | grep -v UUID | grep \w | awk '{print $2}' | tail -n1)
    ironic node-update $IRONIC_NODE add properties/capabilities="boot_mode:$BOOT_MODE"

    # Temporary workaround until bug/1466729 is fixed
    cd /opt/stack/ironic
    git fetch https://rameshg87@review.openstack.org/openstack/ironic refs/changes/36/193436/5 && git cherry-pick FETCH_HEAD
    screen -S stack -p ir-cond -X stuff 
    screen -S stack -p ir-cond -X stuff '/usr/local/bin/ironic-conductor --config-file=/etc/ironic/ironic.conf & echo $! >/opt/stack/status/stack/ir-cond.pid; fg || echo "ir-cond failed to start" | tee "/opt/stack/status/stack/ir-cond.failure"\r'

    # Copy elilo.efi (temporary workaround - add it to devstack)
    DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
    cp $DIR/elilo.efi /opt/stack/data/ironic/tftpboot

    cd /opt/stack/tempest
    export OS_TEST_TIMEOUT=3000

    stop_console
    ILO_IP=$(awk '{print $1}' $ILO_HWINFO_FILE)
    ILO_USERNAME=$(awk '{print $3}' $ILO_HWINFO_FILE)
    ILO_PASSWORD=$(awk '{print $4}' $ILO_HWINFO_FILE)
    ssh-keygen -R $ILO_IP
    ssh-keyscan -H $ILO_IP > ~/.ssh/known_hosts
    sshpass -p $ILO_PASSWORD ssh $ILO_IP -l $ILO_USERNAME vsp >& $LOGDIR/console &

    number_of_machines=$(wc -l $ILO_HWINFO_FILE | awk '{print $1}')
    for i in `seq 1 $number_of_machines`
    do
        tox -eall -- --concurrency=1 test_baremetal_server_ops
    done

    # Wait for all jobs to complete
    # wait
    stop_console

    #cd /opt/stack/devstack
    #./unstack.sh

}

update_proliantutils
run_stack
#run_stack iscsi_ilo iscsi_ilo-bios $BIOS_HWINFO
#run_stack agent_ilo agent_ilo-bios $BIOS_HWINFO
#run_stack pxe_ilo pxe_ilo-bios $BIOS_HWINFO
#run_stack iscsi_ilo iscsi_ilo-uefi $UEFI_HWINFO
#run_stack pxe_ilo pxe_ilo-uefi $UEFI_HWINFO
