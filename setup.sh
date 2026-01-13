#!/bin/bash
cd vm/
terraform init
terraform apply --auto-approve
terraform output  kubeconfig > ../k8s/config.yaml
sed -i -n '/apiVersion/,$p' ../k8s/config.yaml
sed -i '/EOT/,$d' ../k8s/config.yaml

echo "Sleeping for 60s to give nodes time to settle..."
sleep 60
cd ../k8s
export KUBECONFIG=./config.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml

helm install \
 cilium \
 cilium/cilium \
 --version 1.18.3 \
 --namespace kube-system \
 --set ipam.mode=kubernetes \
 --set kubeProxyReplacement=true \
 --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
 --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
 --set cgroup.autoMount.enabled=false \
 --set cgroup.hostRoot=/sys/fs/cgroup \
 --set k8sServiceHost=localhost \
 --set k8sServicePort=7445 \
 --set=gatewayAPI.enabled=true \
 --set=gatewayAPI.enableAlpn=true \
 --set=gatewayAPI.enableAppProtocol=true
kubectl -n kube-system delete daemonset kube-proxy
kubectl -n kube-system delete daemonset kube-flannel

while [[ $(kubectl get nodes --no-headers | grep -c ' NotReady') -gt 0 ]]; do
  echo "Waiting for nodes to be Ready..."
  sleep 5
done
echo "All nodes are Ready! Unleash CHAOS!"