#!/bin/bash -x

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
evalInstructions=$(python $DIR/parsing_n_executing_jenny_data.py "$JENNY_INPUT")
eval "$evalInstructions"

export IRONIC_DEPLOY_DRIVER_ISCSI_WITH_IPA=True
export IRONIC_IPA_RAMDISK_DISTRO=fedora
export DEFAULT_INSTANCE_USER=ubuntu
chmod 777 $WORKSPACE
rm -rf $WORKSPACE/*
export LOGDIR=$WORKSPACE
sudo -E -H -u ubuntu stdbuf -oL -eL $DIR/gate.sh

