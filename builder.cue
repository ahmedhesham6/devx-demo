package main

import (
	"stakpak.dev/devx/v2alpha1"
	"stakpak.dev/devx/v1/transformers/kubernetes"
	"stakpak.dev/devx/v1/traits"
	argocd "stakpak.dev/devx/v1/transformers/argocd"
)

builders: v2alpha1.#Environments & {
	prod: v2alpha1.#StackBuilder & {
		drivers: kubernetes: output: dir: ["."]
		config: {
			defaultSecurityContext: {
				runAsUser:  64198
				runAsGroup: 1000
				fsGroup:    1000
			}
			imagePullSecrets: [
				{
					name: "azure-image-pull-secret"
				},
			]
			gateway: {
				name:   "default"
				public: true
				addresses: [
					"",
				]
				listeners: {
					"http": {
						port:     80
						protocol: "HTTP"
					}
				}
			}
			namespace: "default"
		}
		flows: {
			"ignore-secret": match: traits: Secret: null
			"ignore-k8s-cluster": pipeline: [{traits.#KubernetesCluster}]
			"k8s/argo-helm": pipeline: [
				argocd.#AddHelmRelease,
				kubernetes.#SetOutputSubdir & {
					subdir: "build/prod/platform"
				},
			]
			"k8s/argo-k8s": pipeline: [
				kubernetes.#AddKubernetesResources,
				kubernetes.#SetOutputSubdir & {
					$metadata: labels: output: string
					subdir: $metadata.labels.output
				},
			]
			"k8s/add-deployment": {
				exclude: traits: Cronable: null
				pipeline: [kubernetes.#AddDeployment & {
					if config.imagePullSecrets != _|_ {
						k8s: imagePullSecrets: config.imagePullSecrets
					}
				},
					kubernetes.#SetOutputSubdir & {
						subdir: "build/prod/app"
					},
				]
			}
			"k8s/add-service": pipeline: [kubernetes.#AddService]
			"k8s/add-ingress": pipeline: [ kubernetes.#AddIngress & {
				ingressClassName: "openshift-default"
				http: gateway: config.gateway
			},
				kubernetes.#SetOutputSubdir & {
					subdir: "build/prod/app"
				},
			]
			"k8s/add-namespace": pipeline: [kubernetes.#AddNamespace & {
				namespace: config.namespace
			}]
			"k8s/add-pod-securitycontext": pipeline: [kubernetes.#AddPodSecurityContext & {
				podSecurityContext: config.defaultSecurityContext
			}]
		}
	}
}
