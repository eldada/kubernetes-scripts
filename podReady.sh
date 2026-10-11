#!/usr/bin/env bash

## Simple script to check if pod is really ready.
# Check the pod is in 'Running' phase and all its containers are ready
# Exit with 0 if ready. Exit with 1 if not ready (or on any error).

# UNCOMMENT this line to enable debugging
# set -xv

NAMESPACE=default
POD=
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Get pod readiness (pod is Running and all containers ready).
                 Exit with 0 if the pod is ready. Exit with 1 if not (or if the pod can't be checked).

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>      : Namespace.  Default: ${NAMESPACE}
-p | --pod       <name>      : Pod to check
-h | --help                  : Show this usage

Examples:
========
$ ${SCRIPT_NAME} --namespace test --pod nginx-1234asdf

END_USAGE
}

# Make sure an option has a value
requireValue () {
    [[ $# -ge 2 && -n "$2" ]] || errorExit "Option $1 requires a value"
}

# Process command line options. See usage above for supported options
processOptions () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n | --namespace)
                requireValue "$@"
                NAMESPACE="$2"
                shift 2
            ;;
            -p | --pod)
                requireValue "$@"
                POD="$2"
                shift 2
            ;;
            -h | --help)
                usage
                exit 0
            ;;
            *)
                usage >&2
                exit 1
            ;;
        esac
    done

    [[ -n "${POD}" ]] || errorExit "Must provide pod name (--pod <POD>)"
}

# Test kubectl is installed
testKubectl () {
    command -v kubectl > /dev/null || errorExit "kubectl not found in PATH"
}

checkPod () {
    local phase
    local ready_status

    phase=$(kubectl get pod -n "${NAMESPACE}" "${POD}" --output=jsonpath='{.status.phase}') || errorExit "Failed getting pod ${POD} in namespace ${NAMESPACE}"
    [[ "${phase}" == Running ]] || return 1

    ready_status=$(kubectl get pod -n "${NAMESPACE}" "${POD}" --output=jsonpath='{.status.containerStatuses[*].ready}') || errorExit "Failed getting pod ${POD} in namespace ${NAMESPACE}"

    # Leave only unique words
    ready_status=$(echo "${ready_status}" | tr ' ' '\n' | sort -u)

    [[ "${ready_status}" == true ]] && return 0

    return 1
}

main () {
    processOptions "$@"
    testKubectl

    checkPod && exit 0
    exit 1
}

######### Main #########

main "$@"
