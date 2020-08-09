#!/bin/bash

# Go over all namespaces in a cluster and check if they are empty of workloads and controller objects

# All workload oobjects to search for
OBJECTS=pods,jobs,cronjobs,deployments,daemonsets,statefulsets

# Temp files for the grep later on
NS_ALL=namespaces-all.txt
NS_WL=namespaces-with-workloads.txt

# Get list of all namespaces
kubectl get ns --no-headers -o=custom-columns=NAME:.metadata.name > ${NS_ALL}

# Get list of all namespaces with any workload in them
kubectl get ${OBJECTS} --no-headers --all-namespaces -o=custom-columns=NAMESPACE:.metadata.namespace | sort -u > ${NS_WL}

# Use grep to find all values in NS_ALL that are not in NS_WL (these are empty namespaces)
grep -vf ${NS_WL} ${NS_ALL}

# Cleanup temp files
rm -f ${NS_WL} ${NS_ALL}
