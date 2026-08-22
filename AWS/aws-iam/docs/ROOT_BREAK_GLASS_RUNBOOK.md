# Root and Break-Glass Runbook

## Scope

Use this runbook only for:

- A documented AWS task that requires root credentials.
- Recovery from an identity-provider outage when no approved administrative role can be used.
- A centralized privileged root action approved by the security team.

## Preconditions

- Incident/change ticket exists.
- Two authorized approvers are present.
- The exact action, account, expected result, and rollback are documented.
- CloudTrail logging and security monitoring are operational.
- The session is time-bounded.

## Procedure

1. Verify the AWS account ID and account purpose.
2. Confirm that an administrator role cannot perform the task.
3. Obtain approval from security and platform/account ownership.
4. Retrieve the password and MFA/recovery mechanism through the enterprise vault.
5. Sign in from an approved, patched workstation.
6. Perform only the approved action.
7. Sign out and close the browser session.
8. Review CloudTrail events for the session.
9. Confirm that no access keys, users, roles, or policies were created unexpectedly.
10. Rotate or re-seal credentials according to policy.
11. Attach evidence to the ticket.
12. Conduct a brief post-use review.

## Prohibited actions

- Routine administration.
- Application deployment.
- Creating root access keys.
- Sharing root credentials over chat, email, or tickets.
- Storing MFA seeds or recovery codes in the repository.
- Using root to bypass change control.
