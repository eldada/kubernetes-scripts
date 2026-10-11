#!/usr/bin/env bash

# UNCOMMENT this line to enable debugging
# set -xv

## Execute a command on a list of pods

EXEC="df -h"
NAMESPACE=
PODS=
CONTAINER=
QUIET=false
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Run a given command on all pods matching criteria.
                 The command runs directly (not in a shell), so pipes, redirects and variables are not interpreted.
                 To use these, run a shell: --exec "sh -c 'ps aux | grep java'"

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>               : Namespace to run in (required)
-p | --pods <regex>                   : Pods to run on (regex matched against the pod name).  Default: all pods in the namespace
-c | --container <string>             : Container to run on (name).                            Default: first container in the pod
-x | --exec <string>                  : Command to execute.                                    Default: ${EXEC}
-q | --quiet                          : Don't print the progress messages (they go to stderr)
-h | --help                           : Show this usage

Examples:
========
${SCRIPT_NAME} --namespace demo --pods artifactory-primary --exec "uptime" --container artifactory-app
${SCRIPT_NAME} --namespace demo --exec "sh -c 'ps aux | grep java'"

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
            -x | --exec)
                requireValue "$@"
                EXEC="$2"
                shift 2
            ;;
            -p | --pods)
                requireValue "$@"
                PODS="$2"
                shift 2
            ;;
            -c | --container)
                requireValue "$@"
                CONTAINER="$2"
                shift 2
            ;;
            -q | --quiet | --quite)
                QUIET=true
                shift 1
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

    [[ -n "${NAMESPACE}" ]] || errorExit "Must provide a namespace (--namespace <NAMESPACE>)"
    if [[ -z "${CONTAINER}" && "${QUIET}" == false ]]; then
        echo "WARNING: No container set. Kubectl will default to the first container in the pod" >&2
    fi
}

# Split a command string into words, honoring single and double quotes.
# Quotes are removed. A backslash escapes the next character outside quotes.
# Nothing is expanded or executed here.
splitCommand () {
    local input=$1
    local word='' quote='' escaped=0
    local i char

    exec_cmd=()
    for (( i=0; i<${#input}; i++ )); do
        char=${input:i:1}
        if [[ ${escaped} -eq 1 ]]; then
            word+="${char}"
            escaped=0
            continue
        fi
        if [[ -n ${quote} ]]; then
            if [[ ${char} == "${quote}" ]]; then
                quote=
            else
                word+="${char}"
            fi
            continue
        fi
        case ${char} in
            \\)
                escaped=1
            ;;
            \' | \")
                quote=${char}
            ;;
            [[:space:]])
                if [[ -n ${word} ]]; then
                    exec_cmd+=("${word}")
                    word=
                fi
            ;;
            *)
                word+="${char}"
            ;;
        esac
    done

    [[ ${escaped} -eq 0 ]] || errorExit "Trailing backslash in --exec command"
    [[ -z ${quote} ]] || errorExit "Unbalanced quote in --exec command"
    [[ -z ${word} ]] || exec_cmd+=("${word}")
    [[ ${#exec_cmd[@]} -gt 0 ]] || errorExit "Command to execute is empty"
}

# Test kubectl is installed and the connection to a cluster
testConnection () {
    command -v kubectl > /dev/null || errorExit "kubectl not found in PATH"
    kubectl cluster-info > /dev/null 2>&1 || errorExit "Connection to cluster failed"
}

runCommandOnPods () {
    local list
    local pod
    local failed=0
    local -a exec_cmd
    local -a container_args=()

    list=$(kubectl get pods -n "${NAMESPACE}" --no-headers -o custom-columns=NAME:.metadata.name) || errorExit "Failed getting the pods list in namespace ${NAMESPACE}"
    if [[ -n "${PODS}" ]]; then
        list=$(echo "${list}" | grep -E -- "${PODS}")
    fi
    [[ -n "${list}" ]] || errorExit "No pods found in namespace ${NAMESPACE} matching '${PODS}'"

    # Split the command to words, keeping quoted arguments together
    splitCommand "${EXEC}"
    [[ -n "${CONTAINER}" ]] && container_args=(-c "${CONTAINER}")

    for pod in ${list}; do
        if [[ "${QUIET}" == false ]]; then
            printf '\n---- Pod: %s' "${pod}" >&2
            [[ -n "${CONTAINER}" ]] && printf ' (Container: %s)' "${CONTAINER}" >&2
            printf '\n' >&2
        fi

        # Don't pass stdin so kubectl can't swallow the terminal input
        kubectl exec -n "${NAMESPACE}" "${pod}" "${container_args[@]}" -- "${exec_cmd[@]}" < /dev/null || { echo "WARNING: Command failed on pod ${pod}" >&2; failed=1; }
    done

    return ${failed}
}

main () {
    processOptions "$@"
    [[ "${QUIET}" == true ]] || echo "Running command '${EXEC}' on pods in namespace ${NAMESPACE}" >&2
    testConnection
    runCommandOnPods
}

######### Main #########

main "$@"
