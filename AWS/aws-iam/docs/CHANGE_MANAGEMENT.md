# IAM Change Management

## Pull-request requirements

Every IAM-related pull request must include:

- Business reason.
- Affected accounts, environments, principals, actions, and resources.
- Whether the change creates new access.
- Threat/abuse case considered.
- Validation and simulation evidence.
- Deployment sequence.
- Rollback procedure.
- Required approvers.
- Expiration/review date for temporary access.

## High-risk changes

Require security approval for:

- `Action: "*"` or broad `Resource: "*"`.
- `iam:PassRole`.
- Trust-policy changes.
- Administrator permission sets.
- OIDC/SAML providers.
- SCPs, RCPs, permission boundaries.
- KMS administration/decryption scope.
- Security service disablement.
- Cross-account or public resource policies.
- Root-access management.

## Emergency changes

Emergency changes may use an expedited path but must:

- Be linked to an incident.
- Be deployed by an emergency role.
- Be time-limited where possible.
- Be reconciled into Git immediately.
- Receive retrospective review within one business day.
