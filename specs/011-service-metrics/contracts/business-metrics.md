# Contract: Business Metrics

## Series

| Family | Service | Type | Labels | Increments by one when | Never counts |
| --- | --- | --- | --- | --- | --- |
| `todo_api_todos_created_total` | `todos-api` | counter | none | a signed-in user's todo is stored and the create request answers successfully | a request rejected before storing (for example, missing or invalid JWT) |
| `todo_api_todos_deleted_total` | `todos-api` | counter | none | a signed-in user deletes a todo whose id existed | a delete for an id that does not exist (the request still answers 204) |
| `auth_api_sign_ins_total` | `auth-api` | counter | `outcome` = `accepted` or `rejected` | `accepted`: the login handler returns a token; `rejected`: the login fails with wrong credentials (HTTP 401) | a login that fails for any other reason (HTTP 500), probes, scrapes |

No business series carries a user name, todo id, todo content, token, or
password as a label.

## Business row

`infrastructure/grafana/dashboards/golden-signals.yaml` contains a `row`
panel titled `Business` followed by two time-series panels:

| Panel | Queries |
| --- | --- |
| Todos created and deleted (per 5m) | `sum(increase(todo_api_todos_created_total[5m]))`, `sum(increase(todo_api_todos_deleted_total[5m]))` |
| Sign-ins by outcome (per 5m) | `sum by (outcome) (increase(auth_api_sign_ins_total[5m]))` |

No alert rule reads these series.

## Validation

`tests/contract/observability.sh` fails when the rendered Grafana root lacks
the `Business` row or any of the three series in its queries.
