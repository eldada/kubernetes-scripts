#!/bin/bash

# Go over all namespaces in a cluster and check if they are empty of workloads and controller objects

OBJECTS=pods,jobs,cronjobs,deployments,daemonsets,statefulsets

echo "Empty namespaces:"
for n in $(kubectl get ns --no-headers -o=custom-columns=NAME:.metadata.name); do
    if [ -z "$(kubectl get ${OBJECTS} -n ${n} --no-headers 2> /dev/null)" ]; then
        echo "${n}"
    fi
done
