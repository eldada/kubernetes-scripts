#!/bin/bash
# set -x

## Simple script to check if pod is really ready.
# Check containers are ready
# Return 1 if not ready. Return 0 if ready.

NAMESPACE=default
POD=

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Get pod readiness (all containers ready).
                 Exit with 0 of all containers are ready. Exit with 1 if not.

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>      : Namespace. Default: default
-p | --pod       <name>      : Pod to check
-h | --help                  : Show this usage

Examples:
========
$ ${SCRIPT_NAME} --namespace test --pod nginx-1234asdf

END_USAGE

    exit 1
}

# Process command line options. See usage above for supported options
processOptions () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n | --namespace)
                NAMESPACE="$2"
                shift 2
            ;;
            -p | --pod)
                POD="$2"
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

    if [[ -z "${POD}" ]]; then errorExit "Pod not passed"; fi
}

checkPod () {
    local ready_status
    ready_status=$(kubectl get pod -n ${NAMESPACE} ${POD} --output=jsonpath='{.status.containerStatuses[*].ready}')

    # Leave only unique words
    ready_status=$(echo "$ready_status" | tr ' ' '\n' | sort -u)

    [[ $ready_status =~ ^true$ ]] && return 0

    return 1
}

main () {
    processOptions "$@"

    checkPod && exit 0
    exit 1
}

######### Main #########

main "$@"
