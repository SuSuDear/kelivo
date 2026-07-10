---
description: Create or improve Codex-style agent skills packaged as a directory with SKILL.md and optional resources.
---
# Skill Creator

Use this built-in skill when the user wants to create, edit, review, or package an agent skill.

A skill is a directory containing a `SKILL.md` file plus optional scripts, references, templates, or other resources. Keep the skill focused on one reusable workflow.

When creating a skill:

1. Ask for the workflow goal and trigger conditions if they are not clear.
2. Write a concise `description` in front matter so the host can decide when to load the skill.
3. Put operational instructions in `SKILL.md`; do not include secrets.
4. Add scripts or references only when they materially reduce repeated work.
5. Prefer progressive disclosure: keep the always-loaded description short and put detailed instructions in `SKILL.md`.
6. Include validation steps or examples when useful.

Suggested structure:

```text
skill-name/
  SKILL.md
  scripts/
  references/
  templates/
```

The final answer should summarize the skill name, trigger description, files created or changed, and how to test it.
