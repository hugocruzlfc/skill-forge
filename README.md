# Skill Forge

A personal collection of AI agent skills, built, tested and refined around the tools, frameworks and workflows I use every day.

The repository is organized by technology and designed to work with multiple AI coding assistants, including Claude Code, GitHub Copilot and Codex.

## Skills

| Skill                                                                    | Technology | Description                                                                                                     |
| ------------------------------------------------------------------------ | ---------- | --------------------------------------------------------------------------------------------------------------- |
| [ado-task-context](skills/azure/ado-task-context)                        | Azure      | Captures Azure Boards work items and prepares evidence-backed repository context.                               |
| [nextjs-feature-architecture](skills/nextjs/nextjs-feature-architecture) | Next.js    | Defines practical feature-based architecture and code organization conventions for Next.js App Router projects. |

## Installation

Clone the repository:

```bash
git clone https://github.com/hugocruzlfc/skill-forge.git
cd skill-forge
```

### macOS / Linux / WSL

Install all skills:

```bash
./install.sh
```

Install a specific skill:

```bash
./install.sh nextjs-feature-architecture
```

Choose the installation target explicitly:

```bash
./install.sh --target claude
./install.sh --target agents
./install.sh --target both
```

List available skills:

```bash
./install.sh --list
```

### Windows (PowerShell 7+)

Install all skills:

```powershell
./install.ps1
```

Install a specific skill:

```powershell
./install.ps1 -Skill nextjs-feature-architecture
```

Choose the installation target:

```powershell
./install.ps1 -Target claude
./install.ps1 -Target agents
./install.ps1 -Target both
```

List available skills:

```powershell
./install.ps1 -List
```

### Installation targets

| Target      | Installation directory  | Assistant                |
| ----------- | ----------------------- | ------------------------ |
| `claude`    | `~/.claude/skills`      | Claude Code              |
| `agents`    | `~/.agents/skills`      | GitHub Copilot and Codex |
| `both`      | Both directories        | Multiple assistants      |
| Custom path | User-provided directory | Custom setup             |

Skills are installed as symbolic links by default, so changes in this repository are reflected immediately.

Use `--copy` (Bash) or `-Copy` (PowerShell) to install independent copies.

Use `--force` (Bash) or `-Force` (PowerShell) to replace existing skill directories.

## Repository structure

```text
skills/
├── azure/
│   └── ado-task-context/
│       ├── SKILL.md
│       ├── README.md
│       ├── assets/
│       └── scripts/
└── nextjs/
    └── nextjs-feature-architecture/
        ├── SKILL.md
        └── feature-anatomy.md

templates/
└── SKILL.template.md

docs/
└── conventions.md

install.sh
install.ps1
```

Each skill lives in its own directory. Technology folders are used to group related skills.

## Creating a skill

1. Choose a technology group, such as `nextjs`, `azure` or `react`.
2. Create a skill directory under `skills/<technology>/<skill-name>/`.
3. Add a `SKILL.md` file using `templates/SKILL.template.md` as a starting point.
4. Set the frontmatter `name` to exactly match the skill directory name.
5. Add supporting files only when needed, such as `references/`, `scripts/` or `assets/`.

Example:

```text
skills/
└── react/
    └── react-component-patterns/
        ├── SKILL.md
        └── references/
            └── component-guidelines.md
```

See [docs/conventions.md](docs/conventions.md) for naming, authoring and contribution conventions.

## Development

Install development dependencies:

```bash
pnpm install
```

Commits follow [Conventional Commits](https://www.conventionalcommits.org/) and are validated with Husky and commitlint.

Allowed types:

`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

Example:

```bash
feat(nextjs-feature-architecture): add feature composition guidelines
```

## License

[MIT](LICENSE)
