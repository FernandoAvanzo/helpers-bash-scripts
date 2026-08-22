# IAM Role and Permission-Set Catalog

| Name pattern | Principal | Purpose | Credential type | Boundary |
|---|---|---|---|---|
| `Administrator` permission set | Identity Center admin group | Rare account administration | Temporary | Organization guardrails |
| `SecurityAudit` permission set | Security group | Read security posture and evidence | Temporary | Read-only |
| `Operations` permission set | Operations group | Routine workload operations | Temporary | No IAM/org management |
| `org-github-deploy-<env>` | GitHub OIDC | Create and execute approved change sets | Temporary | Pipeline policy |
| `org-cfn-execution-<scope>` | CloudFormation | Provision approved stack resources | Temporary | Scoped execution policy |
| `app-<app>-<env>-runtime` | AWS service/workload | Runtime AWS API access | Temporary | Workload boundary |
| `app-<app>-<env>-migrations` | Controlled job | Database/schema migrations | Temporary | Workload boundary |
| `org-emergency-admin` | Emergency IAM user or federation | IdP outage | Temporary after assume-role | Alerted and time-bounded |

## Required metadata

Every customer-managed role should include:

- Owner
- Application
- Environment
- ManagedBy
- DataClassification
- Expiration or review date where temporary
- Ticket/change reference in description when applicable

## Trust-policy checklist

- Exact principal or provider.
- Exact OIDC audience.
- Repository, branch, tag, or environment subject restriction.
- `aws:SourceAccount`/`aws:SourceArn` for service delegation where supported.
- `sts:ExternalId` for third parties.
- No wildcard principal without a defensible resource-policy design.
