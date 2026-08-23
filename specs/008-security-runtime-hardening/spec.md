# Feature Specification: Runtime Security Hardening

**Feature Branch**: `feat/security-runtime-hardening`

**Created**: 2026-08-23

**Status**: Draft

**Input**: User description: "Add the MicroTodoSuite runtime security baseline that constitution principle 10 marks as claim-gated and deferred: deploy Falco for in-cluster runtime threat detection (syscall-level anomaly detection using its default/community rules) with alerts routed to the same Slack channel the observability alerting already uses; run kube-bench as a periodic CIS Kubernetes Benchmark audit against the eks-dev cluster; run kube-hunter as a periodic penetration-test-style scan for exploitable cluster misconfigurations. All three must be GitOps-managed, namespace-scoped, pinned-and-vendored, and Audit-before-Enforce where applicable, matching the same economical profile and conventions already used for keda/cert-manager/kyverno/prometheus. Findings must produce real, actionable evidence (not a passing claim with no output), and must not block or mutate existing business workloads."

## Clarifications

### Session 2026-08-23

- Q: Which syscall-capture driver does Falco use on eks-dev? → A: Modern eBPF probe. It is Falco's current recommended default for standard EKS node kernels (Amazon Linux 2/2023) and does not require compiling a kernel-version-specific module, which would be fragile against node upgrades in a Karpenter/managed-node-group cluster.
- Q: Which mode does kube-bench run in, given eks-dev's control plane is AWS-managed and not directly accessible? → A: The `eks` target profile. It skips control-plane checks the cluster cannot actually audit (AWS owns that plane) and evaluates only what applies: worker-node configuration and cluster policies, avoiding false FAILs on inapplicable components.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Get notified in Slack when a workload does something suspicious at runtime (Priority: P1)

As an on-call operator, I receive a Slack notification when a running
container does something a container normally never does (spawn a shell,
write to a sensitive system path, open an unexpected outbound connection),
without needing to watch anything.

**Why this priority**: Every other supply-chain and admission control this
suite already has (Trivy, Cosign, Kyverno) proves an image is trustworthy
*before* it runs; none of them can see what a already-admitted container
actually does once it's running. Falco is the one piece that closes that
gap, and it delivers value the moment it's live, independent of the audit
tools below.

**Independent Test**: With Falco reconciled and healthy, exec into a running
business-workload container and run a command Falco's default ruleset
flags (e.g. spawn an interactive shell), and observe a Slack message
referencing the pod, namespace, and the specific rule that fired, within
the alert's configured delivery window.

**Acceptance Scenarios**:

1. **Given** Falco is synchronized and healthy on every node, **When** a
   container performs an action matched by Falco's default/community rules
   (e.g. a shell spawned inside a container, a write to `/etc`), **Then**
   Falco emits a finding identifying the exact rule, pod, namespace, and
   process.
2. **Given** a Falco finding is emitted, **When** Falcosidekick forwards it,
   **Then** a message appears in the same Slack channel the observability
   alerting (spec 006) already uses, within 1 minute of the finding.
3. **Given** Falco is running, **When** business workloads operate under
   normal conditions with no anomalous syscalls, **Then** no finding is
   emitted for them and their own liveness/readiness/startup probes remain
   unaffected.

---

### User Story 2 - Prove the cluster meets the CIS Kubernetes Benchmark (Priority: P2)

As a security auditor, I can run a CIS Kubernetes Benchmark scan against the
live cluster and get a real pass/fail report per control, rather than an
assumption that the cluster is configured correctly.

**Why this priority**: A CIS benchmark audit is a point-in-time check, not a
continuously running control like Falco; it delivers real value on its own
(a documented compliance baseline) but is naturally sequenced after the
always-on runtime detection above.

**Independent Test**: Run kube-bench against the live `eks-dev` cluster and
retrieve a report listing each CIS control's PASS/FAIL/WARN status and the
remediation text for any failing control, without modifying any cluster
resource.

**Acceptance Scenarios**:

1. **Given** kube-bench is scheduled to run periodically, **When** a run
   completes, **Then** it produces a report with a real PASS/FAIL/WARN
   result and remediation guidance for every applicable CIS control, not a
   placeholder or empty output.
2. **Given** a completed kube-bench run, **When** the report is reviewed,
   **Then** every FAIL is either remediated in a follow-up change or
   recorded as an explicit, justified, time-bounded exception - never
   silently dropped.
3. **Given** kube-bench has run, **When** its Job completes, **Then** it
   leaves no long-running privileged workload behind (the audit access is
   temporary, not a standing elevated permission).

---

### User Story 3 - Prove the cluster has no obvious exploitable misconfiguration (Priority: P3)

As a security auditor, I can run kube-hunter against the live cluster and
get a real report of exploitable attack paths it found (or confirmation it
found none), rather than assuming the cluster is safe from common
Kubernetes attack techniques.

**Why this priority**: kube-hunter is the most exploratory of the three
controls (it actively probes for exploitable paths rather than checking
static configuration or watching live syscalls) and is the natural last
layer once the always-on detection and the static configuration audit are
both in place.

**Independent Test**: Run kube-hunter in internal (in-cluster) mode against
the live `eks-dev` cluster and retrieve a report of any discovered
vulnerabilities with their severity, without it actually exploiting or
disrupting any finding it discovers.

**Acceptance Scenarios**:

1. **Given** kube-hunter is scheduled to run periodically, **When** a run
   completes, **Then** it produces a report of discovered vulnerabilities
   (or an explicit "none found") with severity for each finding, not a
   placeholder output.
2. **Given** a completed kube-hunter run, **When** the report is reviewed,
   **Then** every finding is either remediated or recorded as an explicit,
   justified, time-bounded exception.
3. **Given** kube-hunter runs in internal/passive mode, **When** it probes a
   discovered path, **Then** it does not actually exploit the path or
   disrupt a running business workload.

### Edge Cases

- Falco's default ruleset can flag a legitimate platform action (e.g. a
  Kyverno or cert-manager controller doing something its rules consider
  anomalous); a noisy default rule MUST be tuned or explicitly exempted,
  not silenced by disabling Falco broadly.
- Falco must keep running (and alerting) even if Falcosidekick or the Slack
  webhook is temporarily unreachable; a delivery failure must not silently
  disable detection.
- A kube-bench or kube-hunter Job that fails to complete (crashes, times
  out) MUST be visible as a failed run, never interpreted as "no findings."
- kube-bench and kube-hunter's audit access MUST NOT be able to modify
  cluster state; their RBAC is read-only, and any temporary elevated access
  they need is scoped to the Job's lifetime, not standing.
- If a later feature removes or is renamed the Slack channel/webhook this
  reuses (spec 006 US3), Falco alert delivery must fail visibly (a clearly
  failed delivery), not fall back to silently dropping findings.
- Running kube-hunter against a live, shared, multi-namespace cluster (the
  economical profile's `dev`/`staging`/`prod` namespaces on one cluster)
  must not be mistaken for permission to probe or disrupt another team's
  workload; scope is this suite's own namespaces only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Falco MUST be deployed as a GitOps-managed, node-level runtime
  detector using its default/community ruleset and the modern eBPF driver
  (per the Clarifications session), covering every node the `eks-dev`
  cluster runs (this suite's namespaces).
- **FR-002**: Falco findings MUST be forwarded to the same Slack channel
  used by the observability alerting (spec 006 US3) via Falcosidekick,
  within 1 minute of the finding.
- **FR-003**: Falco's Slack delivery MUST use the same ESO-delivered webhook
  secret pattern already established (spec 006), never a value committed
  to Git; a second, separate webhook MAY be used if operationally simpler,
  but it MUST follow the identical ExternalSecret/SecretStore pattern.
- **FR-004**: Falco MUST run in Audit mode first (detection and alerting
  only); enforcement/blocking behavior (if ever added) MUST be a separate,
  reviewed revision, per this project's established Audit-before-Enforce
  convention.
- **FR-005**: kube-bench MUST run as a scheduled, GitOps-managed Job against
  the live `eks-dev` cluster on a recurring interval, using the `eks` target
  profile (per the Clarifications session, since the control plane is
  AWS-managed and not directly auditable), producing a report with a
  PASS/FAIL/WARN result and remediation text per applicable CIS control.
- **FR-006**: kube-hunter MUST run as a scheduled, GitOps-managed Job in
  internal (in-cluster, non-destructive) mode against `eks-dev` on a
  recurring interval, producing a report of discovered vulnerabilities (or
  an explicit "none found") with severity.
- **FR-007**: kube-bench's and kube-hunter's Jobs MUST use the minimum RBAC
  needed to read cluster/node configuration, MUST NOT be able to mutate any
  resource, and MUST NOT leave a standing privileged workload after the Job
  completes.
- **FR-008**: Every component in this feature MUST be namespace-scoped,
  vendored and checksum-pinned (or provenance-recorded where no genuine
  upstream bundle exists) exactly like the existing add-ons, and registered
  through `eks-dev`'s explicit activation list, never auto-discovered.
- **FR-009**: No component in this feature MAY introduce a service mesh or
  mTLS dependency, matching the economical profile's prohibition on Istio.
- **FR-010**: A finding from any of the three tools MUST result in either a
  remediation or an explicit, justified, time-bounded documented exception;
  a finding MUST NOT be silently dropped or hidden by narrowing scan scope.
- **FR-011**: Final verification MUST capture live evidence - a real Falco
  finding delivered to Slack, a real kube-bench report, and a real
  kube-hunter report - never a claim based on rendered manifests alone.
- **FR-012**: Repository validation MUST fail on unpinned component
  versions, missing vendor checksums or provenance records, a Falco rule
  disabled outright instead of tuned/exempted, or a claimed capability
  without corresponding live evidence.

### Key Entities

- **Runtime finding**: A Falco detection event - the rule that fired, the
  pod/namespace/process involved, and its delivered Slack notification.
- **Benchmark report**: The output of one kube-bench run - per-CIS-control
  PASS/FAIL/WARN status and remediation text.
- **Vulnerability report**: The output of one kube-hunter run - discovered
  exploitable paths (or none) with severity.
- **Documented exception**: A finding from any of the three tools that is
  not remediated, with an explicit justification and a review date.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Falco is Synced/Healthy on every node within 10 minutes of the
  final commit for this feature reaching `gitops`.
- **SC-002**: A deliberately triggered anomalous action (e.g. a shell
  spawned in a running container) produces a Slack notification within 1
  minute, identifying the correct pod, namespace, and rule.
- **SC-003**: A completed kube-bench run produces a report covering 100% of
  applicable CIS controls with a real PASS/FAIL/WARN result, not a
  placeholder.
- **SC-004**: A completed kube-hunter run produces a report of real findings
  (or an explicit "none found"), with zero disruption to any running
  business workload.
- **SC-005**: Every FAIL/vulnerability finding from the first kube-bench and
  kube-hunter runs is either remediated or recorded as a documented,
  justified exception - zero silently-dropped findings.
- **SC-006**: Every retained vendor bundle matches its recorded SHA-256
  checksum, and all repository render and validation checks pass.
- **SC-007**: Live evidence connects every success claim above to the exact
  `gitops` revision and cluster observation it was drawn from; no capability
  is reported successful from configuration alone.

## Assumptions

- This feature targets the live `eks-dev` cluster's shared node pool and
  this suite's own namespaces (`microtodo-*`, `observability`), mirroring
  how the observability feature (006) scoped itself; auditing namespaces
  outside this suite's ownership is out of scope.
- Falco's default/community ruleset is the starting baseline; custom rules
  tuned to this suite's specific workloads are explicit follow-up work, not
  part of this feature's success criteria.
- kube-bench and kube-hunter run on a recurring schedule (e.g. daily or
  weekly via a Kubernetes CronJob), not continuously and not only once;
  the exact interval is a planning-phase decision, not a spec-level one.
- Falco alerting reuses the Slack channel and webhook-delivery mechanism
  spec 006 already established; if that channel is unavailable, this
  feature provisions its own webhook through the identical ESO pattern
  rather than inventing a new delivery mechanism.
- No ingress/TLS work is included: this suite currently has no business
  Ingress resource at all (access is `kubectl port-forward` only, per spec
  006's FR-017), so there is nothing to add TLS to yet; that remains
  explicit future work tied to whenever a real Ingress is introduced.
- Enforcement (blocking, not just alerting) for any of the three tools is
  out of scope; this feature is detection and audit only, matching
  constitution principle 10's "claim-gated" framing for these specific
  tools.
