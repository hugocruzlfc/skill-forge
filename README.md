# skill-forge

My personal forge of Claude skills: created, tuned and battle-tested
for the stacks I use every day (React, Python/FastAPI, Azure).

## Install

```bash
git clone https://github.com/hugocruzlfc/skill-forge.git
cd skill-forge

# Linux / macOS / WSL
./install.sh                      # all skills -> ~/.claude/skills
./install.sh -t agents            # all skills -> ~/.agents/skills (Copilot)
./install.sh ado-task-context     # a single skill
```

```powershell
# Windows (PowerShell 7+)
./install.ps1
./install.ps1 -Target agents -Skill ado-task-context
```

Skills are symlinked, so edits in the repo apply instantly.
Use `--copy` / `-Copy` if you prefer an independent copy.

## Skills

| Skill                                         | Stack | What it does                                                          |
| --------------------------------------------- | ----- | --------------------------------------------------------------------- |
| [`ado-task-context`](skills/ado-task-context) | Azure | Turns an Azure Boards work item into evidence-backed planning context |

## Adding a new skill

Copy `templates/SKILL.template.md` into `skills/<tech>-<topic>/SKILL.md` and edit it.
The folder name must match the `name` in the frontmatter.
