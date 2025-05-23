#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# IBM Cloud CLI login
function ibmcloud_login {
    export IBMCLOUD_CLI=ibmcloud
    export IBMCLOUD_HOME=/output
    region="${LEASED_RESOURCE}"
    rg=$1
    export region
    "${IBMCLOUD_CLI}" config --check-version=false
    echo "Try to login to ${rg}..."
    "${IBMCLOUD_CLI}" login -r ${region} -g ${rg} --apikey @"${CLUSTER_PROFILE_DIR}/ibmcloud-api-key"
}

configFile="${SHARED_DIR}/install-config.yaml"
PUBLISH=$(yq-go r "${configFile}" "publish")
echo "publish: ${PUBLISH}"

if [ -z "${PUBLISH}" ] || [ X"${PUBLISH}" == X"External" ]; then
    echo "skipping checking for External cluster"
    exit 0
fi

RESOURCE_GROUP=$(jq -r .ibmcloud.resourceGroupName ${SHARED_DIR}/metadata.json)

ibmcloud_login ${RESOURCE_GROUP}

critical_check_result=0

#check the load balances 'Is public' all are false
mapfile -t lbs < <(ibmcloud is lbs --output JSON | jq -r '.[]|.name+" "+(.is_public|tostring)')
echo "INFO: lb list is: " "${lbs[@]}"
for lb in "${lbs[@]}"
do
    if [[ ! ${lb} =~ false ]]; then
        echo "ERROR: $lb is not expected value!"
        critical_check_result=1
    fi
done

exit ${critical_check_result}
