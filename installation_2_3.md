# BNK 2.3 quick FLO installation guide
```bash
$ pwd
$ /home/ubuntu/bnkinstall
$ ll
-rw-rw-r--  1 ubuntu ubuntu 1426 May 21 03:40 cne-instance-f5-bnk-instance.yaml
-rw-rw-r--  1 ubuntu ubuntu 3189 May 21 03:28 cne_pull_64.json
-rwxr--r--  1 ubuntu ubuntu  763 May 21 03:26 create-far-pull-secret-manifest.sh
-rwxr--r--  1 ubuntu ubuntu  132 May 21 03:25 env.sh
-rw-rw-r--  1 ubuntu ubuntu  362 May 21 03:29 f5-lifecycle-operator-override-values.yaml
-rwxr--r--  1 ubuntu ubuntu  947 May 21 03:26 get-cne-chart-version.sh
-rw-rw-r--  1 ubuntu ubuntu  664 May 21 03:37 k8s-macvlan-nad.yaml
-rw-rw-r--  1 ubuntu ubuntu  343 May 21 03:44 k8s-nfs-storageclass.yaml
-rw-rw-r--  1 ubuntu ubuntu  824 May 21 03:35 otel-certs.yaml
```
list of all base files for installation
1. 2 k8s yamls for nfs and macvlan net-attach-def creation
2. 1 env.sh script for env varialbeble in installation
3. 2 scriptbash scripts from BNK site for manifest chart and version extraction as well as 
4. 1 bash script for far-pull-secret creation
5. 3 BNK yamls for 1) otel certs creation; 2) f5- flo instlaallationallation; 3) f5 cne instance installation
6. 1 BNK yaml for final step of jwt license creation.
### enable env variable that will be used throughout installation.
```bash
$ source ./env.sh
$ echo CNE_REPO
$ repo.f5.com
```
## First lets load the install the preconditions in k8s.
### a prerequiesite is to install cert-manager v1.19.4
```bash
$ kubectl create -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.4/cert-manager.yaml ; kubectl wait --for=condition=ready pod --all --namespace cert-manager --timeout=120s
pod/cert-manager-cainjector-79dfb57945-ddxlt condition met
pod/cert-manager-f48c47bd-4dvfc condition met
pod/cert-manager-webhook-7ccb49fb7b-87r72 condition met
```
### once cert-manager is installed. Continue to create CNE self signed clusterissuer.
```bash
$ kubectl apply -f f5-cne-cluster-issuer.yaml
$ kubectl get clusterissuersNAME                        READY   AGE
f5-cne-internal-ca          True    10d
selfsigned-cluster-issuer   True    10d
```
### storageclass creation
```bash
$ cat k8s-nfs-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
etadata:
  name: nfs
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs.csi.k8s.io
parameters:
  server: 10.1.1.4
  share: /mnt/nfs_share
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true 
ountOptions:
  - hard
  - nfsvers=4.0
```
### Apply storageclass
```bash
$ kubectl apply -f k8s-nfs-storageclass.yaml
$ kubectl get storagtegeclass nfs
NAME            PROVISIONER      RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
nfs (default)   nfs.csi.k8s.io   Delete          Immediate           true                   10d
### namespace creation of f5-cne-core and f5-bnk-instance
```bash
$ kubectl create namespace f5-cne-core
$ kubectl create namespace f5-bnk-instance
```
### network-attachment-definition creation for bnk in f5-bnk-instance namespace
### when it is sr-iov or DPU update to appropriate CR content
```bash
$ cat k8s-macvlan-nad.yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
etadata:
  name: external-net
spec:
  config: '{
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "ens6",
      "mode": "passthru",
      "ipam": {
      },
      "logLevel": "debug",
      "logFile": "/var/log/net-attach-external.log"
    }'
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
etadata:
  name: internal-net
spec:
  config: '{
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "ens7",
      "mode": "passthru",
      "ipam": {
      },
      "logLevel": "debug",
      "logFile": "/var/log/net-attach-internal.log"
    }'
```
### Apply net-attach-def. 
```bash
$ kubectl apply -f k8s-macvlan-nad.yaml -n f5-bnk-instance
$ kubectl get net-attach-def -n f5-bnk-instance
```
# 
### Next step is to deploy Flo
### bash script get-cne-chart-version.sh is used in all installation steps to extract the core components and has to be placed in the manifest folder.
```bash
$ pwd
~/bnkinstall/f5-bigip-k8s-manifest-2.3.0-3.2598.3-0.0.170
### all other yamls are also moved here for simplicity
### apply flo now
$ helm install f5-lifecycle-operator oci://$CNE_REPO/charts/f5-lifecycle-operator --version $(./get-cne-chart-version.sh f5-lifecycle-operator) --namespace f5-cne-core
### check if flo  is installed successfully.
$ kubectl get pod -n f5-f5-cne-core
NAME                                    READY   STATUS    RESTARTS      AGE
f5-lifecycle-operator-889d79b7c-mmq96   1/1     Running   1 (18h ago)   2d
```
### next create the CWC authentication
```bash
$ sh cert-gen/gen_cert.sh -s=api-server -a=f5-spk-cwc.f5-cne-core.svc.cluster.local -n=1
$ ll | grep cwc | grep yaml-rw-rw-r-- 1 ubuntu ubuntu  5706 May 21 03:56 cwc-license-certs.yaml
-rw-rw-r-- 1 ubuntu ubuntu  5657 May 21 03:56 cwc-license-client-certs.yaml
### 2 cwc tls certs are created. apply them to cluster in f5-cne-core namespace
$ kubectl create -f cwc-license-certs.yaml -f cwc-license-client-certs.yaml --namespace f5-cne-core
### Check if cwc certs re created.
$ kubectl get secret -n f5-cne-core | grep cwc
cwc-license-certs                               Opaque                           3      9d
cwc-license-client-certs                        Opaque                           3      9d
### Next prepare Otel cert before cneinstance installation.
$ kubectl apply -f otel-certs.yaml -n f5-bnk-instance
$ kubectl get secret -n f5-bnk-instance | grep otelexternal-f5ingotelsvr-secret                  kubernetes.io/tls                3      9d
external-otelsvr-secret                       kubernetes.io/tls                3      9d
### Now lets install cne instance
### check the network devices to be used by BNK cne instance.
$ kubectl get net-attach-def -n f5-bnk-instance
NAME           AGE
external-net   9d
internal-net   9d
### full CR yaml for the installation as exmaple
$ cat cne-instance-f5-bnk-instance.yaml 
apiVersion: k8s.f5.com/v1
kind: CNEInstance
etadata:
  name: f5-bnk-instance
spec:
  product:
    gatewayAPI: true
    type: BNK
  manifestVersion: 2.3.0-3.2598.3-0.0.170
  wholeCluster: true
  dpu:
    enabled: false 
  telemetry:
    loggingSubsystem:
      enabled: true
    metricSubsystem:
      enabled: true
  certificate:
    clusterIssuer: f5-cne-internal-ca
  deploymentSize: Small 
  registry:
    uri: repo.f5.com
    imagePullSecrets:
    - name: far-pull-secret
    imagePullPolicy: IfNotPresent
  networkAttachments:
  - external-net
  - internal-net
  - cnf-net
  storageClassName: nfs
  dynamicRouting:
    enabled: true
  # AFM
  firewallACL:
    enabled: true
  pseudoCNI:
    enabled: true
  # Core dump files
  coreCollection:
    enabled: true
  advanced:
    envDiscovery:
      enabled: false 
      stopOnFail: true
      runAfterSuccess: true
    cneController:
      env:
      - name: "GSLB_DATACENTER_NAME"
        value: "DC1"
    demoMode:
      enabled: true
    maintenanceMode:
      enabled: false
    tmm:
      env:
      - name: TMM_CALICO_ROUTER
        value: default
      - name: TMM_DEFAULT_MTU
        value: "9000"
      - name: ZEBOS_STATE
        value: legacy
      - name: "TMM_MAPRES_ADDL_VETHS_ON_DP"
        value: "TRUE"
    pseudoCNI:
      env:
      - name: EXCLUDE_CIDR
        value: "10.1.1.0/8,10.1.200.0/24,10.1.210.0/24,10.1.220.0/24,10.96.0.0/12,192.168.0.0/16"
```
### deploy CNEinstance
```bash
$ kubectl apply -f cne-instance-${CNE_INSTANCE_NAMESPACE}.yaml --namespace $CNE_INSTANCE_NAMESPACE
cneinstance.k8s.f5.com/f5-bnk-instance created
#check resources are created and installed
$ kubectl get pod -n f5-cne-coreNAME                                    READY   STATUS              RESTARTS      AGE
crd-installer-nrtqh                     0/2     Completed           0             16s
f5-crdconversion-86dd5bd97d-j79hx       0/2     ContainerCreating   0             1s
f5-ipam-ctlr-6964c7c655-bg7tc           0/2     ContainerCreating   0             1s
f5-lifecycle-operator-889d79b7c-mmq96   1/1     Running             1 (18h ago)   2d
f5-observer-0                           0/2     ContainerCreating   0             0s
f5-observer-operator-9f77ddd4f-2nq57    0/2     ContainerCreating   0             0s
f5-rabbit-64479655fb-t8pvt              0/2     ContainerCreating   0             1s
f5-spk-csrc-2gc7r                       0/2     ContainerCreating   0             0s
f5-spk-csrc-6f2ff                       0/2     ContainerCreating   0             0s
f5-spk-csrc-6r7hz                       0/2     ContainerCreating   0             0s
f5-spk-csrc-j5m5x                       0/2     ContainerCreating   0             0s
f5-toda-fluentd-699d895c98-x4b4l        0/1     Init:0/2            0             1s
otel-collector-7975478f56-tcwzp         0/1     ContainerCreating   0             0s
$ kubectl get pod -n f5-bnk-instanceNAME                                 READY   STATUS    RESTARTS      AGE
f5-afm-789ff7bb49-5ht4s              2/2     Running   0             10s
f5-cis-controller-7f9bb9d494-k6mkh   1/1     Running   1 (18h ago)   5d17h
f5-cne-controller-6bcd5c449f-657xj   4/5     Running   0             10s
f5-downloader-66b449488b-7fhn2       3/3     Running   0             10s
f5-dssm-db-0                         2/3     Running   0             9s
f5-dssm-sentinel-0                   2/3     Running   0             9s
f5-tmm-6vlvx                         4/7     Running   0             10s
f5-tmm-788k2                         4/7     Running   0             10s
$ kubect get cneinstance f5-bnk-instance
NAME              AGE
f5-bnk-instance   52s
```
### Next apply the license.
```bash
$ cat f5-cne-cluster-license.yaml 
apiVersion: k8s.f5net.com/v1
kind: License
etadata:
  name: f5-cne-cluster-license
spec:
  operationMode: "connected"
  jwt: "<insert your JWT here>"
$ kubectl apply -f f5-cne-cluster-license.yaml -n f5-cne-core
```
# Wait for a few mins for it to finish the licensing process
```bash
$ kubectl get license -n f5-cne-core
NAME                     STATE    MODE        ENTITLEMENT   ENVIRONMENT   EXPIRY                 DIGITALASSETID                         AGE
f5-cne-cluster-license   Active   connected   eval          production    2026-06-10T06:46:57Z   eda1e85c-037d-4255-a923-847f8e289218   9d
```
# the installation steps are now complete.
