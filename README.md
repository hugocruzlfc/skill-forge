# skill-forge

My personal forge of Claude skills: created, tuned and battle-tested
for the stacks I use every day (React, Python/FastAPI, Azure).

## Install

git clone https://github.com/hugocruzlfc/skill-forge.git
cd skill-forge && ./install.sh

Skills are symlinked into `~/.claude/skills`, so edits in the repo apply instantly.

## Skills

| Skill                      | Stack  | What it does                                 |
| -------------------------- | ------ | -------------------------------------------- |
| `react-component-patterns` | React  | Component structure and hooks conventions    |
| `python-fastapi-endpoint`  | Python | FastAPI endpoints with Pydantic v2 and tests |
| `azure-bicep-iac`          | Azure  | Infrastructure as code with Bicep            |

## Adding a new skill

Copy `templates/SKILL.template.md` into `skills/<tech>-<topic>/` and edit it.
