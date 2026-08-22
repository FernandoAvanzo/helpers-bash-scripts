# Secure AWS Account IAM and DevSecOps Starter

This repository is a secure-by-default starting point for organizing AWS authentication, authorization, IAM roles, permission boundaries, CI/CD federation, and account governance as code.

## Target state

- Root credentials are reserved for root-only and recovery tasks.
- Human access uses AWS IAM Identity Center and temporary role credentials.
- Workloads use IAM roles, service roles, IRSA/EKS Pod Identity, EC2 instance profiles, Lambda execution roles, ECS task roles, or IAM Roles Anywhere.
- CI/CD uses OIDC federation; no long-lived AWS access keys are stored in the repository or CI secret store.
- Permissions are managed as code, reviewed by security owners, validated before deployment, and audited after deployment.
- The structure works for one account now and can expand into AWS Organizations, organizational units, service control policies, and CloudFormation StackSets.

## Repository layout

```text
.
├── cloudformation/
│   ├── iam-baseline.yaml
│   ├── identity-center-permission-sets.yaml
│   └── github-oidc-deployment-role.yaml
├── docs/
│   ├── SECURE_AWS_ACCOUNT_GUIDE.md
│   ├── ROOT_BREAK_GLASS_RUNBOOK.md
│   ├── ROLE_CATALOG.md
│   └── CHANGE_MANAGEMENT.md
├── policies/
│   ├── permissions-boundaries/workload-boundary.json
│   ├── scps/deny-account-departure-and-closure.json
│   ├── scps/deny-root-user-actions.example.json
│   └── trust/github-actions-trust-policy.example.json
├── scripts/
│   ├── inventory-iam.sh
│   └── validate.sh
├── .github/workflows/
│   ├── validate.yml
│   └── deploy.yml
├── .pre-commit-config.yaml
└── CODEOWNERS
```

## Bootstrap order

1. Secure the root user and recovery channels.
2. Enable AWS Organizations, even if you initially have only one workload account.
3. Enable an organization instance of IAM Identity Center.
4. Create identity groups and assign permission sets.
5. Deploy `cloudformation/iam-baseline.yaml`.
6. Create a tightly scoped CloudFormation execution role through a security-approved bootstrap process.
7. Deploy `cloudformation/github-oidc-deployment-role.yaml`.
8. Configure GitHub environment protection and repository variables.
9. Enable the deployment workflow only after a security review.
10. Add SCPs first to a test OU, not directly to production.

## Local validation

Requirements: `bash`, `jq`, `python3`, `cfn-lint`, AWS CLI v2.

```bash
./scripts/validate.sh
```

When AWS credentials are available, the script also calls IAM Access Analyzer policy validation.

## Deploy the account baseline

```bash
aws cloudformation deploy \
  --stack-name iam-baseline-core \
  --template-file cloudformation/iam-baseline.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    OrganizationName=example \
    Environment=shared
```

## Deploy Identity Center permission sets

```bash
aws cloudformation deploy \
  --stack-name iam-identity-center-permission-sets \
  --template-file cloudformation/identity-center-permission-sets.yaml \
  --parameter-overrides \
    InstanceArn=arn:aws:sso:::instance/ssoins-REPLACE_ME
```

Assignments are intentionally not hard-coded because IAM Identity Center group IDs and target account IDs differ by organization. Add `AWS::SSO::Assignment` resources in a reviewed organization-specific overlay.

## Deploy the GitHub OIDC role

Create and approve a CloudFormation execution role first. Then:

```bash
aws cloudformation deploy \
  --stack-name iam-github-oidc \
  --template-file cloudformation/github-oidc-deployment-role.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GitHubOrg=YOUR_ORG \
    GitHubRepo=YOUR_REPO \
    GitHubRef=refs/heads/main \
    CloudFormationExecutionRoleArn=arn:aws:iam::123456789012:role/org-cloudformation-execution \
    StackNamePrefix=iam-
```

## Important safety notes

- The permissions boundary is a maximum-permissions guardrail, not a grant. Every workload role still needs a least-privilege identity policy.
- The example root-user SCP can cause lockout. Review centralized root access and privileged root sessions before attachment.
- SCPs do not grant permissions and do not apply to the Organizations management account.
- Test all guardrails in a sandbox/test OU with failure tolerance set to zero before wider rollout.
- Do not create root access keys. Do not commit credentials, account recovery secrets, MFA seeds, or private keys.
