#!/usr/bin/env bash

# Go over all nodes in a cluster and extract the load average from them by running
#  > cat /proc/loadavg
# in the kube-proxy pods (since they run as a Daemonset).

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}

# Check we have the kube-proxy daemonset, so we can run commands on its pods
kubectl get ns kube-system > /dev/null 2>&1 || errorExit "Namespace kube-system not found, or you don't have permission to get it"
kubectl get ds kube-proxy -n kube-system > /dev/null 2>&1 || errorExit "Daemonset kube-proxy not found in kube-system"

pods=$(kubectl get po -n kube-system | grep kube-proxy | awk '{print $1}' | tr '\n' ' ')

# Header for the CSV output
echo "Node, Load 1 min, Load 5 min, Load 15 min, CPU, High load"

# Go over the pods and extract data
for p in $pods; do
    alert="-"
    node=$(kubectl describe po -n kube-system $p | grep Node: | awk '{print $2}')
    read -r load1 load5 load15 dummy1 dummy2 cpu <<< $(kubectl exec -n kube-system $p -c kube-proxy -- sh -c "cat /proc/loadavg; echo ' '; nproc" 2> /dev/null | tr -d '\n')


    # Convert load5 to integer for easier comparison later
    load_int=${load5%.*}

    # If load > number of cpu, it should be marked with YES as "High load"
    if [[ $load_int -gt $cpu ]]; then alert="YES"; fi

    echo "$node, $load1, $load5, $load15, $cpu, $alert"
done

