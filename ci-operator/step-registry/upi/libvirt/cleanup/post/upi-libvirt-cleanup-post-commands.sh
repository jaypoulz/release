#!/bin/bash

# install jq if not installed
if ! [ -x "$(command -v jq)" ]; then
    mkdir -p /tmp/bin
    JQ_CHECKSUM="2f312b9587b1c1eddf3a53f9a0b7d276b9b7b94576c85bda22808ca950569716"
    curl -Lo /tmp/bin/jq "https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64"

    actual_checksum=$(sha256sum /tmp/bin/jq | cut -d ' ' -f 1)
    if [ "${actual_checksum}" != "${JQ_CHECKSUM}" ]; then
        echo "Checksum of downloaded JQ didn't match expected checksum"
        exit 1
    fi

    chmod +x /tmp/bin/jq
    export PATH=${PATH}:/tmp/bin
fi

# ensure LEASED_RESOURCE is set
if [[ -z "${LEASED_RESOURCE}" ]]; then
  echo "Failed to acquire lease"
  exit 1
fi

# ensure leases file is present
if [[ ! -f "${CLUSTER_PROFILE_DIR}/leases" ]]; then
  echo "Couldn't find lease config file"
  exit 1
fi

# ensure hostname can be found
HOSTNAME="$(jq -r ".\"${LEASED_RESOURCE}\".hostname" "${CLUSTER_PROFILE_DIR}/leases")"
if [[ -z "${HOSTNAME}" ]]; then
  echo "Couldn't retrieve hostname from lease config"
  exit 1
fi

REMOTE_LIBVIRT_URI="qemu+tcp://${HOSTNAME}/system"
VIRSH="mock-nss.sh virsh --connect ${REMOTE_LIBVIRT_URI}"
echo "Using libvirt connection for $REMOTE_LIBVIRT_URI"

# Test the remote connection
mock-nss.sh virsh -c ${REMOTE_LIBVIRT_URI} list

set +e

# Remove conflicting domains
for DOMAIN in $(${VIRSH} list --all --name | grep "${LEASED_RESOURCE}")
do
  ${VIRSH} destroy "${DOMAIN}"
  ${VIRSH} undefine "${DOMAIN}"
done

# Remove conflicting volumes
# TODO: Make `multiarch-ci-pool` a default in the ref definition
for VOLUME in $(${VIRSH} vol-list --pool multiarch-ci-pool | grep "${LEASED_RESOURCE}" | awk '{ print $1 }' || true)
do
  # TODO: Make `multiarch-ci-pool` a default in the ref definition
  ${VIRSH} vol-delete --pool multiarch-ci-pool --vol ${VOLUME}
done

# Remove source volume (delete this before merge)
${VIRSH} vol-delete --pool multiarch-ci-pool --vol "$(${VIRSH} vol-list --pool multiarch-ci-pool | grep rhcos | awk '{ print $1 }' || true)"

# Remove conflicting pools
for POOL in $(${VIRSH} pool-list --all --name | grep "${LEASED_RESOURCE}")
do
  ${VIRSH} pool-destroy "${POOL}"
  ${VIRSH} pool-delete "${POOL}"
  ${VIRSH} pool-undefine "${POOL}"
done

# Remove conflicting networks
for NET in $(${VIRSH} net-list --all --name | grep "${LEASED_RESOURCE}")
do
  ${VIRSH} net-destroy "${NET}"
  ${VIRSH} net-undefine "${NET}"
done

# Detect conflicts
CONFLICTING_DOMAINS=$(${VIRSH} list --all --name | grep "${LEASED_RESOURCE}")
CONFLICTING_VOLUMES=$(${VIRSH} vol-list --pool multiarch-ci-pool | grep "${LEASED_RESOURCE}" | awk '{ print $1 }' || true)
CONFLICTING_POOLS=$(${VIRSH} pool-list --all --name | grep "${LEASED_RESOURCE}")
CONFLICTING_NETWORKS=$(${VIRSH} net-list --all --name | grep "${LEASED_RESOURCE}")

set -e

if [ ! -z "${CONFLICTING_DOMAINS}" ] || [ ! -z "${CONFLICTING_VOLUMES}" ] || [ ! -z "${CONFLICTING_POOLS}" ] || [ ! -z "${CONFLICTING_NETWORKS}" ]; then
  echo "Could not ensure clean state for lease ${LEASED_RESOURCE}"
  echo "Conflicting domains: $CONFLICTING_DOMAINS"
  echo "Conflicting volumes: $CONFLICTING_VOLUMES"
  echo "Conflicting pools: $CONFLICTING_POOLS"
  echo "Conflicting networks: $CONFLICTING_NETWORKS"
  exit 1
fi