# Full-Profile Stage Evidence Template

Copy `evidence.json` into a timestamped `evidence/runs/<timestamp>-<stage-id>/`
directory and replace every template value with output from the exact reviewed
stage. Keep paths relative to the repository when the artifact is safe to
commit. An external artifact may use an absolute path during validation, but
the committed evidence must retain only its redacted metadata, storage-location
reference, and SHA-256 digest.

Never commit or attach any of the following to a Git evidence bundle:

- Terraform state, state backups, binary saved plans, or full plan JSON;
- kubeconfigs, cloud or GitHub tokens, private keys, or certificate keys;
- plaintext secret values, value-derived hashes, environment dumps, or shell
  traces that could contain credentials;
- unredacted provider configuration or plan output containing sensitive values.

Each accepted bundle must include a passing named approval artifact, current
cloud identity, pre- and post-stage economical baselines, the exact redacted
resource/action counts, quota and Infracost evidence when infrastructure
changes, desired/live success evidence, a controlled failure result, and a
tested rollback. Run:

```bash
scripts/managed/validate-full-profile-evidence.sh \
  evidence/runs/<timestamp>-<stage-id>/evidence.json
```

The validator reads only the checked-in schema, recomputes every declared
artifact checksum, and rejects an accepted decision if a required check or
requirement is not passing.
