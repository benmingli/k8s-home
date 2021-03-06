local kube = import "kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "utils.libsonnet";

{
  namespace:: {
    metadata+: { namespace: "kube-system" },
  },

  kube_proxy: {
    [arch]: $.kube_proxyTmpl { arch: arch }
    for arch in ["amd64", "arm", "arm64", "ppc64le"]
  },

  kube_proxyTmpl:: kube.DaemonSet("kube-proxy") + $.namespace {
    local this = self,
    arch:: error "arch is unset",

    metadata+: {
      name: "%s-%s" % [super.name, this.arch],
    },

    spec+: {
      template+: utils.CriticalPodSpec + utils.PromScrape(10249) {
        spec+: {
	  nodeSelector: {
	    "beta.kubernetes.io/arch": this.arch,
	  },
          dnsPolicy: "ClusterFirst",
          hostNetwork: true,
          restartPolicy: "Always",
          schedulerName: "default-scheduler",
          serviceAccount: "kube-proxy",
          serviceAccountName: self.serviceAccount,
          tolerations: utils.toleratesMaster +
          [{
            effect: "NoSchedule",
            key: "node.cloudprovider.kubernetes.io/uninitialized",
            value: "true",
          }],
          volumes_+: {
            kube_proxy:{
              configMap: {
                defaultMode: kube.parseOctal("420"),
                name: "kube-proxy",
              },
            },
            xtables_lock: kube.HostPathVolume("/run/xtables.lock", "FileOrCreate"),
            lib_modules: kube.HostPathVolume("/lib/modules"),
          },
          containers_: {
            kube_proxy: kube.Container("kube-proxy") {
              image: "gcr.io/google_containers/kube-proxy-%s:v1.9.10" % this.arch,
              command: ["/usr/local/bin/kube-proxy"],
              args_+: {
                "kubeconfig": "/var/lib/kube-proxy/kubeconfig.conf",
                "cluster-cidr": "10.244.0.0/16",
                "hostname-override": "$(NODE_NAME)",
                // https://github.com/kubernetes/kubernetes/issues/53754
                //"metrics-bind-address": "$(POD_IP):10249",
              },
              env_+: {
                NODE_NAME: kube.FieldRef("spec.nodeName"),
                POD_IP: kube.FieldRef("status.podIP"),
              },
              ports_+: {
                metrics: {containerPort: 10249},
              },
              securityContext: {
                privileged: true,
              },
              volumeMounts_+: {
                kube_proxy: {mountPath: "/var/lib/kube-proxy"},
                xtables_lock: {mountPath: "/run/xtables.lock"},
                lib_modules: {mountPath: "/lib/modules", readOnly: true},
              },
            },
          },
        },
      },
    },
  },
}
