## Install Cilium with Helm

```bash
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
```
