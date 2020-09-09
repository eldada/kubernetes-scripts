#!/bin/bash

# UNCOMMENT this line to enable debugging
# set -xv

## Simple script to check if pod is really ready.
# Check status is 'Running' and that all containers are ready.
# Return 1 if not ready. Return 0 if ready.

# pod is the pod name
pod=$1
[ -z "${pod}" ] && echo "ERROR: Pod name not passed" && exit 1

# ns is namespace. Defaults to 'default'
ns=$2
[ -z "${ns}" ] && ns='default'

# Return code
result=1

# Get the pod record from 'kubectl get pods'
p=$(kubectl get pods --namespace ${ns} | grep "${pod}")

if [ -n "${p}" ]; then
    ## Uncomment to see output later down the script
    # pod_name=$(echo -n "${p}" | awk '{print $1}')
    ready=$(echo -n "${p}" | awk '{print $2}')
    ready_actual=$(echo -n "${ready}" | awk -F/ '{print $1}')
    ready_max=$(echo -n "${ready}" | awk -F/ '{print $2}')
    status=$(echo -n "${p}" | awk '{print $3}')

    ## Uncomment to see output
    # echo "... pod ${pod_name}; ready is ${ready}; ready_actual is ${ready_actual}; ready_max is ${ready_max}; status is ${status}"
    if [ "${ready_actual}" == "${ready_max}" ] && [ "${status}" == "Running" ]; then
        result=0
    fi
else
    echo "ERROR: Pod ${pod} not found"
fi

## Uncomment to see output
# echo "Result: ${result}"

exit ${result}
