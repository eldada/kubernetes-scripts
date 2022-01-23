#!/usr/bin/env bash

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}

# Check we have the kube-proxy daemonset so we can run commands on its pods
kubectl get ns kube-system > /dev/null 2>&1 || errorExit "Namespace kube-system not found"
kubectl get ds kube-proxy -n kube-system > /dev/null 2>&1 || errorExit "Daemonset kube-proxy not found in kube-system"

pods=$(kubectl get po -n kube-system | grep kube-proxy | awk '{print $1}' | tr '\n' ' ')

# Header for the CSV output
echo "Node, Load 1 min, Load 5 min, Load 15 min, CPU, High load"

# Go over the pods and extract data
for p in $pods; do
    alert="-"
    node=$(kubectl describe po -n kube-system $p | grep Node: | awk '{print $2}')
    line=$(kubectl exec -n kube-system $p -- sh -c "cat /proc/loadavg | awk '{print \$1 \" \" \$2 \" \" \$3 \" \"}' ; nproc" | tr -d '\n')
    load1=$(echo $line | awk '{print $1}')
    load5=$(echo $line | awk '{print $2}')
    load15=$(echo $line | awk '{print $3}')
    cpu=$(echo $line | awk '{print $4}')

    # Round down the load1 so to convert it to integer for easier comparison later
    load_int=$(echo "$load1" | sed 's/\..*//g')

    # If load > number of cpu, it should be marked with YES as "High load"
    if [[ $load_int -gt $cpu ]]; then alert="YES"; fi

    echo "$node, $load1, $load5, $load15, $cpu, $alert"
done

