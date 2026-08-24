# Data Model: Full Multi-Cloud Platform Rollout

This feature does not add an application database. The model describes versioned desired state and evidence records shared across Terraform, GitOps, CI, and runbooks.

## RuntimeProfile

Represents one operational architecture that may run concurrently with another.

| Field | Type | Rules |
| --- | --- | --- |
| `name` | enum | `economical` or `full`; immutable identity. |
| `isolation_model` | enum | `shared-cluster-namespaces` for economical; `dedicated-cluster-vpc` for full. |
| `mesh_mode` | enum | `none` for economical; `istio-strict-mtls` for full. |
| `required_capabilities` | set | Exact GitOps capability names accepted for this profile. |
| `traffic_authorized` | boolean | Full defaults false; true requires the final traffic gate. |
| `retirement_authorized` | boolean | False for both profiles in this feature. |

## EnvironmentDestination

One logical environment at one physical destination.

| Field | Type | Rules |
| --- | --- | --- |
| `id` | string | `<profile>-<environment>-<cloud>`, globally unique. |
| `profile` | reference | Exactly one `RuntimeProfile`. |
| `environment` | enum | `dev`, `staging`, or `prod`; AKS DR consumes `prod`. |
| `destination_role` | enum | `primary` or `dr`; only AKS uses `dr`. |
| `cloud` | enum | `aws` or `azure`. |
| `account_or_subscription` | string | AWS must equal `916491575487`; Azure must match authenticated approved input. |
| `region` | string | `us-east-1` for AWS; verified approved Azure location for DR. |
| `cluster_name` | string | Unique physical name; `microtodosuite-demo-full` maps only to full staging. |
| `network_cidr` | CIDR | Non-overlapping across all managed and discovered networks. |
| `pod_service_cidrs` | object/null | AKS-only verified pod, service, and DNS ranges; none may overlap discovered connected networks. |
| `network_policy_engine` | enum | `vpc-cni` with network-policy enforcement for full EKS; `azure-cni-overlay-cilium` for AKS. |
| `state_scope` | reference | Exactly one locked `StateScope`. |
| `gitops_root` | path | Exactly one in-cluster root path. |
| `active_environment_count` | integer | `1` for every full destination. |
| `public_access_cidrs` | set<CIDR> | No `0.0.0.0/0`; every full managed control plane initially equals the approved four-entry set. |
| `capacity_budget` | reference | Required for every cluster. |
| `lifecycle_status` | enum | `planned`, `foundation-ready`, `bootstrapped`, `platform-ready`, `workload-ready`, `accepted`, `blocked`, `retired`. |

Validation: an `EnvironmentDestination` cannot advance past `planned` without an accepted stage gate; full staging cannot refer to any physical cluster other than `microtodosuite-demo-full`; AKS DR has `environment=prod` and `destination_role=dr`, uses production configuration and release identity, and remains a distinct destination.

## StateScope

Defines exclusive Terraform ownership.

| Field | Type | Rules |
| --- | --- | --- |
| `backend_kind` | enum | `s3` or `azurerm`. |
| `backend_container` | string | Existing approved bucket/container; never stored with access secrets. |
| `key` | string | Unique across all roots. |
| `region` | string | Must match the actual backend. |
| `encryption_key` | string/null | Exact KMS ARN for S3; Azure service-managed/account-approved encryption for Blob. |
| `locking_enabled` | boolean | Must be true before plan/apply. |
| `owner_root` | path | Exactly one Terraform root. |
| `last_external_backup` | artifact reference | Required immediately before an approved apply that changes state. |

## SharedAccountResource

An account-level singleton consumed by many destinations but changed by one state.

| Field | Type | Rules |
| --- | --- | --- |
| `resource_id` | string | Stable cloud identifier or known name. |
| `kind` | enum | Service ECR repository, platform-mirror ECR repository, GitHub/AKS OIDC provider, shared IAM role, environment/notification/Grafana/Sonar secret container, hosted zone, or transit egress resource. |
| `owner_state` | reference | Exactly one `StateScope`; existing application singletons use dev state. |
| `consumer_states` | set<reference> | May read outputs/data only. |
| `trust_subjects` | set | Exact issuer, audience, and service-account/repository identities. Shared IRSA roles may list exact cluster issuers; the publisher keeps GitHub-only trust. Wildcards are forbidden unless the spec explicitly names one. |
| `prevent_destroy` | boolean | True for registries, secret containers, hosted zone, and other protected singletons. |

## SecretTransfer

One value-blind, OIDC-authenticated replication of the approved production runtime-secret inventory.

| Field | Type | Rules |
| --- | --- | --- |
| `id` | string | Immutable workflow-run identity. |
| `source_arns` | set | Exactly the ARNs resolved for `microtodosuite/prod/auth-api-secrets`, `microtodosuite/observability/alertmanager-slack-webhook`, `microtodosuite/security/falcosidekick-slack-webhook`, and `microtodosuite/observability/grafana-admin`. |
| `target_vault` | cloud identifier | Exactly the Terraform-output Azure DR Key Vault. |
| `target_names` | set | Exactly `microtodosuite-prod-auth-api-secrets`, `microtodosuite-observability-alertmanager-slack-webhook`, `microtodosuite-security-falcosidekick-slack-webhook`, and `microtodosuite-observability-grafana-admin`. |
| `workflow_identity` | object | Exact GitHub repository/environment/reusable-workflow claims and short-lived AWS/Azure OIDC sessions. |
| `source_versions` | map | Non-secret version identifiers only. |
| `target_versions` | map | Non-secret version identifiers only. |
| `jwt_value_match` | boolean | Computed only by an in-process equality comparison without retaining, hashing, or printing either value; must be true before AKS workload activation. |
| `value_artifacts` | integer | Must equal zero across logs, outputs, caches, artifacts, Git, Terraform state, and evidence. |
| `status` | enum | `pending`, `seeded`, `verified`, `blocked`, or `rotated`. |

State transition: `pending -> seeded -> verified`; any identity, inventory, equality, cleanup, or ExternalSecret-readiness failure produces `blocked`. Rotation creates a new immutable run and cannot overwrite its evidence with value material.

## ClusterRegistration

The reviewed value contract used by one in-cluster ArgoCD root.

| Field | Type | Rules |
| --- | --- | --- |
| `cluster_id` | string | Matches one `EnvironmentDestination`. |
| `repo_url` | URI | `https://github.com/MicroTodoSuite/microservice-app-gitops.git`. |
| `revision` | string | Protected `main` after bootstrap; bootstrap evidence records the exact merged SHA. |
| `destination_server` | URI | `https://kubernetes.default.svc`. |
| `planned_activation` | object | Exactly one `{env, profile, server}` declaration for a full root; metadata only and never an Application generator input. |
| `activations` | list | Empty only at the recorded bootstrap revision; afterward exactly equals `planned_activation`. |
| `planned_infrastructure` | ordered list | Complete applicable profile inventory declared even at bootstrap. |
| `infrastructure` | ordered list | Empty at bootstrap, then explicit capability name/path/namespace entries activated in accepted waves; folder discovery is forbidden. |
| `notifications` | object | GitOps-owned ArgoCD Notifications reference to an External Secret, with cluster/environment/application/revision/health context and no secret value. |
| `ingress_binding` | object/null | AKS carries only Terraform-output public-IP name/resource group/FQDN; EKS carries controller-owned NLB identity. |
| `bootstrap_manifest_digest` | digest | SHA-256 of the vendored ArgoCD render. |
| `bootstrap_mutations` | integer | Must equal two for a newly managed cluster. |

## PlatformCapability

One GitOps-owned controller or service.

| Field | Type | Rules |
| --- | --- | --- |
| `name` | string | Stable activation identity. |
| `version` | semver/chart version | Exact; `latest` is forbidden. |
| `source` | URI/path | Vendored source or exact OCI/chart source plus checksum. |
| `namespace` | string | Dedicated where practical. |
| `dependencies` | set<name> | Must be accepted before activation. |
| `resource_budget` | object | Requests, limits, replicas, storage, and retention. |
| `security_contract` | object | ServiceAccount, RBAC, NetworkPolicy, secrets, TLS/mTLS, and policy expectations. Environment JWT containers are dev-owned; each additional EKS cluster has one exact-subject, cluster-qualified reader role for its owned environment. |
| `success_probe` | evidence test | Required before `accepted`. |
| `failure_probe` | evidence test | Required before `accepted`. |
| `rollback_revision` | Git SHA | Required before activation. |
| `status` | enum | `disabled`, `reconciling`, `healthy`, `degraded`, `blocked`, `accepted`. |

State transition: `disabled -> reconciling -> healthy -> accepted`. Any failed dependency or probe produces `blocked`; rollback returns desired state to the prior reviewed revision.

## PlatformImageArtifact

One third-party image used by a GitOps-installed platform capability.

| Field | Type | Rules |
| --- | --- | --- |
| `capability` | reference | Exactly one `PlatformCapability`; every referenced container image has its own record. |
| `upstream_reference` | OCI reference | Exact upstream repository plus immutable `sha256` digest; tags alone are forbidden. |
| `ecr_reference` | OCI reference | Dev-owned `microtodosuite/platform` path plus mirrored digest; required before any full EKS activation. |
| `acr_reference` | OCI reference/null | Required before AKS capability activation; its manifest digest and attached graph must equal ECR. |
| `source_checksum` | digest | Matches the committed toolchain-lock entry. |
| `scan_status` | enum | `pass` only when no blocking vulnerability remains. |
| `signature_identity` | string | Exact approved platform-mirror GitHub Actions OIDC identity; service-CI identity is not interchangeable. |
| `graph_status` | enum | `complete` only when signatures and attestations/SBOMs are discoverable at the destination. |
| `status` | enum | `locked`, `mirrored-ecr`, `signed-ecr`, `mirrored-acr`, `verified`, or `blocked`. |

State transition: `locked -> mirrored-ecr -> signed-ecr`; AKS-bound artifacts then advance through `mirrored-acr -> verified`. A mutable reference, identity mismatch, failed scan, missing graph member, or digest mismatch produces `blocked` and prevents the dependent capability activation.

## CapacityBudget

Bounds cloud and Kubernetes scaling per destination.

| Field | Type | Rules |
| --- | --- | --- |
| `stable_instance_type` | string | `m7i-flex.large` for EKS in this plan. |
| `stable_min_desired_max` | tuple | Staging preserves `2/2/4`; new full dev/prod begin `1/1/2`. |
| `elastic_capacity_type` | enum | `spot` for EKS Karpenter. |
| `elastic_instance_allowlist` | set | Reviewed 2-vCPU/8-GiB-compatible types; no unconstrained family. |
| `elastic_cpu_limit` | quantity | Per cluster; aggregate full-profile Spot limit <= 24 vCPU. |
| `elastic_memory_limit` | quantity | Per cluster and consistent with CPU/type bound. |
| `namespace_limits` | map | ResourceQuota/LimitRange for the owned logical environment. |
| `quota_snapshot` | artifact reference | Current AWS/Azure quota evidence. |

Validation: no capacity pool spans clusters; scaling cannot advance if its quota snapshot is stale or the aggregate bound exceeds the accepted budget.

## ReleaseArtifact

One immutable build promoted without rebuilding.

| Field | Type | Rules |
| --- | --- | --- |
| `service` | enum | One of the five business services. |
| `source_repository` | URI | Exact repository. |
| `source_sha` | Git SHA | Reviewed stable-trunk revision. |
| `version` | string | Release metadata, not deployment identity. |
| `ecr_reference` | OCI reference | Neutral ECR repo plus `sha256` digest. |
| `acr_reference` | OCI reference/null | Required before DR promotion; manifest digest must equal ECR. |
| `sbom_digest` | digest | SBOM bound to the image. |
| `signature_identity` | string | Expected GitHub Actions OIDC signer identity. |
| `test_evidence` | set<artifact> | All required runnable gates. |
| `scan_status` | enum | `pass` only when no blocking vulnerability remains. |

## PromotionRecord

Traces one artifact into one profile/destination.

| Field | Type | Rules |
| --- | --- | --- |
| `artifact` | reference | Exactly one `ReleaseArtifact`. |
| `environment` | enum | `dev`, `staging`, or `prod`; DR promotion remains `prod`. |
| `profile` | enum | `economical` or `full`. |
| `destination` | string | Exact cluster/root; `aks-dr` distinguishes the DR destination. |
| `strategy` | enum | `rolling`, `istio-canary`, or `dr-rolling`. |
| `gitops_pr` | URI | Reviewed PR. |
| `gitops_merge_sha` | Git SHA | Live desired-state revision. |
| `live_digest` | digest | Must equal artifact digest. |
| `analysis_results` | artifacts | Required for production canary. |
| `rollback_sha` | Git SHA/null | Populated during rollback or drill. |
| `status` | enum | `proposed`, `approved`, `reconciling`, `healthy`, `rolled-back`, `blocked`. |

## StageGate

The decision record controlling every delivery stage.

| Field | Type | Rules |
| --- | --- | --- |
| `stage_id` | string | Unique and ordered. |
| `scope` | set | Exact repositories, states, destinations, and capabilities. |
| `baseline` | artifact reference | Economical health and drift captured before work. |
| `plan` | artifact reference | Saved Terraform/GitOps delta; no unexpected destroy. |
| `quota` | artifact reference | Current and sufficient without unapproved increase. |
| `cost` | artifact reference | Infracost plus ceiling or explicit approval. |
| `rollback` | object | Trigger, exact action, owner, and verification. |
| `success_evidence` | set | Desired/live/function proof. |
| `failure_evidence` | set | Controlled failure and recovery proof. |
| `post_baseline` | artifact reference | Economical platform unchanged. |
| `decision` | enum | `pending`, `approved`, `rejected`, `blocked`, `accepted`, `rolled-back`. |
| `approver` | string/null | Human identity for cost/traffic/destructive gates. |

State transition: `pending -> approved -> accepted`; any missing or failing evidence produces `blocked`; an executed rollback produces `rolled-back`. A blocked/rejected stage cannot unlock dependents.

## TrafficDestination

One routable TLS endpoint.

| Field | Type | Rules |
| --- | --- | --- |
| `id` | string | `aws-full-prod` or `azure-dr`. |
| `fqdn` | DNS name | Destination-specific health endpoint. |
| `load_balancer_target` | DNS name | Observed AWS NLB hostname or Terraform-owned Azure static-public-IP FQDN; never a transient address copied from memory. |
| `ingress_binding` | object | AWS controller/NLB identity or Azure public-IP name, resource group, address, and FQDN used by the GitOps Service. |
| `certificate_status` | enum | Must be `trusted-valid` before routing eligibility. |
| `shared_hostname_certificate_status` | enum | Both production destinations must be `trusted-valid` for `app.microtodosuite.online` before its routing records may be planned. |
| `health_path` | path | Service-owned aggregate readiness endpoint. |
| `release_digest` | digest | Must match the paired destination. |
| `routing_region` | string | Route 53 latency region selected from actual endpoint location. |
| `eligible` | boolean | False until all prerequisite gates, destination TLS, and shared-hostname TLS pass. |
| `weight_or_policy` | object | Health-evaluated latency routing only after approval. |

## ChaosExperiment

GitOps-owned, disabled-by-default controlled failure.

| Field | Type | Rules |
| --- | --- | --- |
| `id` | string | Stable scenario identity. |
| `kind` | enum | `pod-termination`, `network-latency`, `redis-saturation`, `aws-prod-outage`. |
| `target_selector` | object | Must select only the approved full destination/workload. |
| `duration` | duration | Explicit and bounded. |
| `abort_conditions` | set | Economical impact, blast-radius escape, SLO breach, or operator abort. |
| `steady_state` | checks | Required before and after. |
| `activation_revision` | Git SHA | Reviewed commit that enables it. |
| `revert_revision` | Git SHA | Required cleanup path. |

## ContinuityDisclosure

Separates service availability from application data behavior.

| Field | Type | Rules |
| --- | --- | --- |
| `exercise_id` | string | References one accepted game-day run. |
| `availability_result` | object | Endpoint success, outage interval, and recovery time. |
| `redis_messages` | object | Created, observed, lost, duplicated, divergent. |
| `todos` | object | Created, observed, lost, duplicated, divergent. |
| `users` | object | Created, observed, lost, duplicated, divergent. |
| `durability_claim` | enum | Must remain `none` for this feature. |
| `operator_acknowledgement` | string | Human acceptance of observed limitations. |

## EvidenceBundle

Machine-readable manifest plus immutable raw evidence.

| Field | Type | Rules |
| --- | --- | --- |
| `schema_version` | string | `1.0.0`. |
| `generated_at` | RFC 3339 timestamp | UTC. |
| `stage_gate` | reference | Exactly one stage. |
| `identities` | object | Sanitized AWS/Azure/Git identities; no token or secret. |
| `artifacts` | list | Path, SHA-256, producer command/workflow, result. |
| `requirements` | map | FR/SC identifier to evidence paths and pass/fail. |
| `decision` | enum | Must agree with all referenced results. |

Validation is defined by `contracts/full-profile-evidence.schema.json`. A missing artifact, checksum mismatch, failed requirement, or unapproved mandatory gate invalidates the bundle.

## Relationships

```text
RuntimeProfile 1 ── * EnvironmentDestination 1 ── 1 StateScope
                            │      │
                            │      ├── 1 ClusterRegistration ── * PlatformCapability ── * PlatformImageArtifact
                            │      ├── 1 CapacityBudget
                            │      └── 0..1 TrafficDestination
                            │
SharedAccountResource * ────┘ (read-only consumer; one owner StateScope)

SharedAccountResource 4 ── * SecretTransfer * ── 1 EnvironmentDestination (AKS DR)

ReleaseArtifact 1 ── * PromotionRecord * ── 1 EnvironmentDestination
StageGate 1 ── * EvidenceBundle
StageGate 1 ── * PlatformCapability / PromotionRecord / ChaosExperiment
ChaosExperiment 1 ── 0..1 ContinuityDisclosure
```
