# Vendored Kiali v2.31.0

`install.yaml` is `helm template` output of the official Kiali Helm chart,
pinned to the immutable image digest from
`scripts/managed/full-profile-toolchain.lock`. `values.yaml` is the exact
override file used to produce it.

Source (`capabilities[].kiali`):

```text
https://kiali.org/helm-charts/kiali-server-2.31.0.tgz
sha256: 6699eeed9ec8026aa3db25b32a8fd1987d1a966481d784eafadc8bdddba771b4
```

Refresh and verify with:

```bash
curl -fL -o kiali-server-2.31.0.tgz https://kiali.org/helm-charts/kiali-server-2.31.0.tgz
echo "6699eeed9ec8026aa3db25b32a8fd1987d1a966481d784eafadc8bdddba771b4  kiali-server-2.31.0.tgz" | sha256sum -c
tar -xzf kiali-server-2.31.0.tgz
helm template kiali kiali-server --namespace kiali -f values.yaml > install.yaml
sha256sum -c SHA256SUMS
```

Generated via `docker run --platform linux/amd64 alpine/helm:3.16.4` to match
the toolchain-lock platform.

**A chart quirk worth recording.** `values.yaml`'s own comment
("use 'sha256' if image_version is a sha256 hash — do NOT prefix this value
with a '@'") is easy to misread as "put the digest in `image_digest`". The
template is actually
`{image_name}{{if image_digest}}@{{image_digest}}{{end}}:{{image_version}}` —
so `image_digest` must hold the literal string `"sha256"` (the algorithm
name) and the hex digest itself goes in `image_version`. Getting this
backwards silently renders an invalid reference
(`name@sha256:<hex>:v2.31.0`, digest and tag both appended) that would only
surface as an `ImagePullBackOff` at apply time — verified by rendering both
ways and inspecting the output before vendoring either.

Overrides from chart defaults, and why:

- `deployment.namespace: kiali` — own namespace, matching this repo's
  one-namespace-per-capability convention (`infrastructure/external-secrets/`,
  `infrastructure/redis/`, etc.), not the `istio-system` control-plane
  namespace.
- `deployment.ingress.enabled: false` — explicit, though it already matches
  the chart default; constitution principle 9/10 requires no public Kiali
  ingress.
- `deployment.network_policy.enabled: true` — already the chart default; kept
  explicit here since it satisfies T083's "network policy" requirement
  natively rather than needing a repository-owned NetworkPolicy alongside.
- `deployment.pod_disruption_budget.spec.minAvailable: 1` — the chart leaves
  this an empty (falsy) map by default, which renders no PodDisruptionBudget
  at all; T083 asks for a resource budget.

`external_services.istio.root_namespace` is left at the chart default (empty
string), which the chart's own helper resolves to `istio-system` — the
namespace `infrastructure/istio/` uses.

Upgrade by regenerating into a new version directory with the command above,
recording the new checksum, and re-running `tests/platform/mesh-policy.bats`.
