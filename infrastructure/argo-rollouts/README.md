# Argo Rollouts

This Argo CD-owned root installs Argo Rollouts 1.9.1 from a checksum-verified
vendored release manifest and pins the controller to an immutable image index.
It also owns `microtodosuite-canary-health`, a shared Kubernetes Job metric used
by all five production Rollouts.

The metric performs a bounded HTTP health request against a service's dedicated
canary Service. Exit code zero promotes the release; exhaustion of the bounded
attempts fails the AnalysisRun, which causes Argo Rollouts to abort and retain
the stable ReplicaSet. It is an availability gate, not a full error-rate
observability claim.

The shared EKS registration activates this root only after its CRDs, digest,
and rendered resources pass the repository contracts. The local Kind pilot
does not activate it.
