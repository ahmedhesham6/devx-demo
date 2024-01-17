package main

import (
	"stakpak.dev/devx/v1"
	"stakpak.dev/devx/v1/traits"
	redisHelm "stakpak.dev/devx/k8s/services/redis"
	minioHelm "stakpak.dev/devx/k8s/services/minio"
	mongoHelm "stakpak.dev/devx/k8s/services/simplemongodb"
	argoapp "stakpak.dev/devx/k8s/services/argocd/components"
)

platform: v1.#Stack & {
	components: {
		cluster: {
			traits.#KubernetesCluster
			k8s: {
				name: "production"
				version: minor: 26
			}
			namespace: "default"
		}
		redis: {
			redisHelm.#RedisChart
			k8s: cluster.k8s
			helm: {
				namespace: cluster.namespace
				values: {
					image: tag:    "7.0.14-debian-11-r0"
					auth: enabled: false
					master: {
						podSecurityContext: enabled:       false
						containerSecurityContext: enabled: false
					}
					replica: {
						podSecurityContext: enabled:       false
						containerSecurityContext: enabled: false
					}
				}
			}

		}
		minio: {
			minioHelm.#MinioChart & {
				helm: {
					values: {
						image: tag: "RELEASE.2023-10-16T04-13-43Z"
						replicas: 3
						resources: {
							requests: memory: "512Mi"
						}
						persistence: {
							size: "5Gi"
						}
						buckets: [
							{
								name:   "demo"
								policy: "none"
								purge:  false
							},
						]
					}
				}
			}
			k8s: cluster.k8s
			helm: {
				namespace: cluster.namespace
			}
		}
		mongo: {
			mongoHelm.#SimpleMongoDBChart
			k8s: cluster.k8s
			helm: {
				namespace: cluster.namespace
				values: {
					image: tag:                        "7.0-debian-11"
					podSecurityContext: enabled:       false
					containerSecurityContext: enabled: false
					arbiter: {
						podSecurityContext: enabled:       false
						containerSecurityContext: enabled: false
					}
					auth: {
						existingSecret: "mongo-secrets"
					}
				}
			}
		}
	}

}

app: v1.#Stack & {
	components: {
		cowsay: {
			traits.#Workload
			containers: default: {
				image: "docker/whalesay"
				command: ["cowsay"]
				args: ["Hello DevX!"]
			}
		}
	}
}

main: v1.#Stack & {
	components: {
		plarformCDApplication: argoapp.#ArgoCDApplication & {
			$metadata: labels: output: "build/prod/main"
			k8s: {
				platform.components.cluster.k8s
				namespace: platform.components.cluster.namespace
			}
			application: {
				name: "demo-platform"
				source: {
					repoURL: "git@github.com"
					path:    "build/prod/platform"
				}
				syncWave: "10"
			}
		}

		appCDApplication: argoapp.#ArgoCDApplication & {
			$metadata: labels: output: "build/prod/main"
			k8s: {
				platform.components.cluster.k8s
				namespace: platform.components.cluster.namespace
			}
			application: {
				name: "demo-app"
				source: {
					repoURL: "git@github.com"
					path:    "build/prod/app"
				}
				syncWave: "20"
			}
		}

	}
}
