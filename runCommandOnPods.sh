#!/bin/bash

# UNCOMMENT this line to enable debugging
# set -xv

## Execute a command on a list of pods

EXEC="df -h"
PODS=
CONTAINER=
SCRIPT_NAME=$0

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Run a given command on all pods matching criteria

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>               : Namespace to analyse
-p | --pods <string>                  : Pods to run on (pattern)
-c | --container <string>             : Container to run on (name)
-x | --exec <string>                  : Command to execute

-h | --help                           : Show this usage

Examples:
========
${SCRIPT_NAME} --namespace demo -pods artifactory-primary -exec "uptime" -container artifactory-app

END_USAGE

    exit 1
}

# Process command line options. See usage above for supported options
processOptions () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n | --namespace)
                NAMESPACE="-n $2"
                shift 2
            ;;
            -x | --exec)
                EXEC="$2"
                shift 2
            ;;
            -p | --pods)
                PODS="$2"
                shift 2
            ;;
            -c | --container)
                CONTAINER="$2"
                shift 2
            ;;
            -h | --help)
                usage
                exit 0
            ;;
            *)
                usage
            ;;
        esac
    done

    [[ -z "${NAMESPACE}" ]] && errorExit "Must provide a namespace"
    [[ -z "${CONTAINER}" ]] && echo "WARNING: No container set. Kubectl will default to the first container in the pod"
}

# Test connection to a cluster by kubectl
testConnection () {
    kubectl cluster-info > /dev/null || errorExit "Connection to cluster failed"
}

runCommandOnPods () {
    local list=

    if [[ -n "${PODS}" ]]; then
        list=$(kubectl get pods ${NAMESPACE} -o custom-columns=:metadata.name | grep ${PODS})
    else
        list=$(kubectl get pods ${NAMESPACE} -o custom-columns=:metadata.name)
    fi
    echo "${list}"

    for l in ${list}; do
        echo -en "\n---- Pod: $l"

#        set -x
        if [[ -n "${CONTAINER}" ]]; then
            echo " (Container: ${CONTAINER})"
            kubectl exec ${NAMESPACE} ${l} -c ${CONTAINER} -- ${EXEC}
        else
            echo
            kubectl exec ${NAMESPACE} ${l} -- ${EXEC}
        fi
#        set +x
    done
}

main () {
    processOptions "$@"
    [ "${QUITE}" == true ] || echo "Running command '${EXEC}' on pods"
    testConnection
    runCommandOnPods
}

######### Main #########

main "$@"
