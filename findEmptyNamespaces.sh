#!/bin/bash

# Go over all namespaces in a cluster and check if they are empty of workloads and controller objects

OBJECTS=pods,jobs,cronjobs,deployments,daemonsets,statefulsets
NS_ALL=ns-all.txt
NS_WL=ns-wl.txt

# Get list of all namespaces
kubectl get ns --no-headers -o=custom-columns=NAME:.metadata.name > ${NS_ALL}

# Get list of all namespaces with any workload in them
kubectl get ${OBJECTS} --no-headers --all-namespaces -o=custom-columns=NAMESPACE:.metadata.namespace | sort -u > ${NS_WL}

# Use grep to find all values in NS_ALL that are not in NS_WL (these are empty namespaces)
grep -vf ${NS_WL} ${NS_ALL}
