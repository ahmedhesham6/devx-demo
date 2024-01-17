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
		common: {
			$metadata: labels: secret: "existing"
			traits.#Secret
			secrets: {
				dbConnection: {
					name:     "application-secrets"
					property: "database-connection-string"
				}
			}
		}
		// Secrets
		minioUser: {
			$metadata: labels: secret: "existing"
			traits.#Secret
			secrets: {
				username: {
					name:     "minio"
					property: "rootUser"
				}
				password: {
					name:     "minio"
					property: "rootPassword"
				}
			}
		}
		mongoUser: {
			$metadata: labels: secret: "existing"
			traits.#Secret
			secrets: {
				password: {
					name:     "mongo-secrets"
					property: "mongodb-root-password"
				}
			}
		}
		// Workloads
		dashboard: {
			traits.#Exposable
			endpoints: default: ports: [{
				port: 4000
			}, {
				port: 4001
			}]
			traits.#Workload
			containers: default: {
				image: "demo-dashboard:latest"
				resources: requests: {
					cpu:    "256m"
					memory: "512M"
				}
			}
		}
		"dashboard-route": {
			traits.#HTTPRoute
			http: {
				listener: "http"
				hostnames: ["dashboard.demo.com"]
				rules: [{
					match: path: "/*"
					backends: [
						{
							name:       dashboard.appName
							endpoint:   dashboard.endpoints.default
							containers: dashboard.containers
							port:       4000
						},
					]
				}]
			}
		}
		logging: {
			traits.#Exposable
			endpoints: default: ports: [{
				port: 8080
			}]
			traits.#Workload
			containers: default: {
				image: "demo-logging:latest"
				resources: requests: {
					cpu:    "256m"
					memory: "512M"
				}
				env: {
					ConnectionStrings__Host:     "mongo-mongodb"
					ConnectionStrings__Port:     "27017"
					ConnectionStrings__Username: "root"
					ConnectionStrings__Password: mongoUser.secrets.password
				}
			}
		}
		webapi: {
			traits.#Exposable
			endpoints: default: ports: [{
				port: 8080
			}]
			traits.#Workload
			containers: default: {
				image: "demo-webapi:latest"
				resources: requests: {
					cpu:    "256m"
					memory: "512M"
				}
				env: {
					ConnectionStrings__DefaultConnection: common.secrets.dbConnection
					ConnectionStrings__Redis:             "redis:6379"
					ConnectedServices__Logging:           "http://logging:8080"

					Minio__Endpoint:  "minio"
					Minio__Port:      "9000"
					Minio__AccessKey: minioUser.secrets.username
					Minio__SecretKey: minioUser.secrets.password
					Minio__Secure:    "false"
				}
			}
		}
		"webapi-route": {
			traits.#HTTPRoute
			http: {
				listener: "http"
				hostnames: ["webapi.demo.com"]
				rules: [{
					match: path: "/*"
					backends: [
						{
							name:       webapi.appName
							endpoint:   webapi.endpoints.default
							containers: webapi.containers
							port:       8080
						},
					]
				}]
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

installer: v1.#Stack & {
	components: {
		installerCDApplication: argoapp.#ArgoCDApplication & {
			$metadata: labels: output: "installer"
			k8s: {
				platform.components.cluster.k8s
				namespace: platform.components.cluster.namespace
			}
			application: {
				name: "demo-installer"
				source: {
					repoURL: "git@github.com"
					path:    "build/prod/main"
				}
			}
		}
	}
}

