---
description: Install, import, or organize Codex-style skills from local files or trusted repositories.
---
# Skill Installer

Use this built-in skill when the user wants to add an existing Codex-style skill to the app or project.

Before installing:

1. Confirm the source path or repository URL.
2. Inspect `SKILL.md` and any scripts before trusting or enabling the skill.
3. Do not install skills that require secrets unless the user explicitly provides a safe environment-variable based setup.
4. Avoid overwriting an existing skill without confirmation.
5. Prefer copying the complete skill directory so relative references continue to work.

A valid skill directory should contain `SKILL.md`. Optional resources may include scripts, references, templates, examples, or fixtures.

After installing, report the installed skill name, location, description, and any manual follow-up required.
