<p align="right">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

# Skills

This directory is reserved for reusable AI-agent skills and workflows. Keep each skill in its own clearly named subdirectory.

Each skill must contain at least `SKILL.en.md` with YAML frontmatter defining `name` and a trigger-focused `description`. Complex skills may add `references/`, `scripts/`, and `assets/`. Keep documentation as plain Markdown and register every added skill in this index.

## Current skills

| Skill | What it does |
| --- | --- |
| [issue-suggestions](issue-suggestions/SKILL.en.md) | After a release, collect the releasing developer's own improvement points and file them as feature request issues against the upstream project. |
| [experience-pr](experience-pr/SKILL.en.md) | After a release, collect reusable development experience and submit it as a documentation pull request. |
| [plays-archive](plays-archive/SKILL.en.md) | After a release, archive the published application into the upstream `plays/` with an AI-generated bilingual summary and a cover image. |
