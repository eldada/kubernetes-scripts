#!/usr/bin/env bash

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}

# Check we have the kube-proxy daemonset so we can run commands on its pods
kubectl get ns kube-system > /dev/null 2>&1 || errorExit "Namespace kube-system not found"
kubectl get ds kube-proxy -n kube-system > /dev/null 2>&1 || errorExit "Daemonset kube-proxy not found in kube-system"

pods=$(kubectl get po -n kube-system | grep kube-proxy | awk '{print $1}' | tr '\n' ' ')

for p in $pods; do
    node=$(kubectl describe po -n kube-system $p | grep Node: | awk '{print $2}')
    echo -n -e "[$node] \t"
    kubectl exec -n kube-system $p -- sh -c "echo -n 'load average: '; cat /proc/loadavg | awk '{print \$1 \" \" \$2 \" \" \$3}' ; echo -n \"  CPU: \" ; nproc" | tr -d '\n'
    echo
done

