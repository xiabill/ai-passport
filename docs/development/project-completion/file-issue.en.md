<p align="right">
  <a href="file-issue.md">简体中文</a> · <strong>English</strong>
</p>

# Action F: File an Issue

This action gathers the releasing developer's own improvement points and files
them as feature request issues against the upstream project. It is one of the six
optional closing actions listed in the [project completion](../project-completion.en.md).

The workflow is driven by the `issue-suggestions` skill. Issues are filed against
the upstream project, not the fork.

## Steps

1. Confirm consent and a GitHub channel (GitHub MCP, a GitHub skill, or `gh`).
2. Collect the developer's own improvement points encountered while developing or
   shipping the release.
3. Deduplicate, drop invalid or resolved points, and categorize by affected area.
4. Match against existing issues and PRs; do not create duplicates.
5. Draft a feature request using the upstream issue template.
6. Present the draft and wait for explicit approval before submitting.
7. Submit through the first available GitHub channel and read the created issue
   back to confirm.

## Safety

- Never include credentials, device QR secrets, private device links, personal
  data, or unsanitized logs.
- Security vulnerabilities go through `.github/SECURITY.en.md`, not a public issue.

## Related documents

- Filing issues reference: [file-issues.en.md](../file-issues.en.md)
- Skill: [issue-suggestions](../../../skills/issue-suggestions/SKILL.en.md)
- Issue template: [.github/ISSUE_TEMPLATE/feature_request.yml](../../../.github/ISSUE_TEMPLATE/feature_request.yml)
