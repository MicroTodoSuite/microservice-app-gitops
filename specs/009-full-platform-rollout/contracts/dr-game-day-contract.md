# Disaster-Recovery Game-Day Contract

## Preconditions

The game day cannot start until all of the following are accepted:

- full AWS production and AKS DR independently reconcile protected `main`;
- both destinations run the same signed production-validated digest for all five services;
- every active GitOps-installed platform image is signed by the approved mirror identity and the AKS ACR graph matches its accepted ECR source;
- trusted ingress TLS, strict internal mTLS, health endpoints, telemetry, alerts, and rollback tests pass;
- Route 53 destination-specific records and health checks pass, while the public active-active switch remains false;
- Azure can reconcile and pull from ACR without AWS runtime dependencies;
- blast radius, operator roles, communication channel, abort conditions, cost window, and rollback revisions are approved;
- a continuity sample set exists for Redis messages, todos, and users.

## GitOps-Owned Scenarios

| Scenario | Target | Maximum duration | Required observation |
| --- | --- | --- | --- |
| Pod termination | one full-production service | 5 minutes | replacement, health, trace/log/metric, no economical impact |
| Network latency | one approved service path | 5 minutes | timeout/retry/circuit behavior and alert |
| Redis saturation | full-production Redis only | 5 minutes | bounded failure, scaling/alert behavior, explicit message loss |
| Complete AWS-production outage | AWS full-prod traffic destination | 10-minute recovery objective | AWS becomes ineligible; AKS remains reconciled and serves all eligible test traffic |
| Azure destination outage | AKS DR endpoint | 10 minutes | Azure becomes ineligible; AWS continues serving |

Each experiment is disabled by default, enabled by a reviewed Git commit, bounded by exact selectors and duration, and removed by Git revert. The economical cluster is never a target.

## Abort Conditions

Abort immediately if:

- any economical Application, pod, endpoint, or Terraform state regresses;
- a selector expands outside the approved namespace/cluster;
- both traffic destinations become unhealthy;
- an experiment exceeds its duration;
- release digests diverge;
- telemetry/health checks become unavailable and fail-closed behavior cannot be established;
- an operator invokes the documented abort.

Abort uses the reviewed Git revert and, if routing was enabled only for the exercise, the approved saved Route 53 rollback plan. No direct workload mutation is permitted.

## Availability Result

Record UTC timeline, DNS/health observations, request success/error rate, p99 latency, last known healthy time, Azure first-success time, recovery time, ArgoCD independence, release digest, alert timing, and whether the ten-minute objective passed.

## Continuity Result

For Redis messages, todos, and users, record sample IDs created before and during the event and count observed, missing, duplicate, and divergent values at AWS and Azure. `durabilityClaim` must be `none`. A successful availability result cannot override continuity loss.

## Traffic Approval Boundary

Passing the game day does not itself enable real production traffic. After the game day, each production destination must obtain and present a trusted `app.microtodosuite.online` certificate through the approved DNS-01 identity while the shared routing record is still absent. The final stage then requires a separate named human approval for the exact Route 53 saved plan. Without it, `enable_active_active` remains false and the feature reports the destinations as ready but traffic-disabled.
