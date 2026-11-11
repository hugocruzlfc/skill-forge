# Azure Boards Task Context

Turn an Azure Boards work item into evidence-backed context for an AI agent
working in a code repository. The skill captures the task, comments and
attachments, reviews relevant repository code, and records requirements,
questions and confirmed decisions. It stops before planning or implementation.

The [skill instructions](./SKILL.md) drive the agent. The bundled collector
downloads evidence; running the collector alone does **not** create the reviewed
context. No AW agents or AW workflow installation are required.

## Prerequisites

- An agent that supports skills, such as GitHub Copilot in a current VS Code
  version. See [VS Code agent skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills).
- [PowerShell 7 or later](https://learn.microsoft.com/powershell/scripting/install/installing-powershell),
  available as `pwsh` on Windows, Linux or macOS. Windows PowerShell 5.1 is not
  supported. The collector does not require additional PowerShell modules.
- Network access to Azure DevOps Services and an account permitted to read the
  target work item and its project.
- A personal access token (PAT) in the `COPILOT_ADO_PAT` environment variable,
  available to the process executing the collector.

The collector supports `dev.azure.com` and organization-specific
`*.visualstudio.com` work-item URLs. Azure DevOps Server and custom hosts are not
supported. Reading PDF, Office or other attachments depends on safe readers
already available to the agent; the skill does not install them automatically.

## Install the Skill

Choose one location and place the **entire** `ado-task-context` folder there:

| Scope                         | Location                                        |
| ----------------------------- | ----------------------------------------------- |
| Personal, across repositories | `~/.agents/skills/ado-task-context/`            |
| Shared with one project       | `<repository>/.github/skills/ado-task-context/` |
| Alternative project location  | `<repository>/.agents/skills/ado-task-context/` |

On Windows, `~` means your user home directory. Keep `SKILL.md`, `scripts/`,
`assets/` and this README together. Do not install into VS Code's extensions
directory or keep conflicting personal and project copies active.

A future skills collection can group source folders by purpose, but the selected
skill must still be installed at a supported discovery location. Merely cloning
a collection into an arbitrary folder does not make every skill discoverable.

Open the **repository whose code you want analyzed**, not the skill's source
folder. In Copilot Chat, check that `/ado-task-context` is available. If absent,
check the location, folder name, current VS Code skill support and reload the
window after installation.

## Configure Azure Boards Access

### Create a PAT

1. Sign in to the intended Azure DevOps organization. Open **User settings >
   Personal access tokens > New Token**.
2. Select that organization, a descriptive name and a limited expiration.
3. Select the minimum scope **Work Items > Read** (`vso.work_read`); expand the
   scope list if necessary. Do not grant Full access or Code permissions for
   this collector.
4. Create the token and configure it directly in your local environment using
   one of the methods below. Never paste it into agent chat.

The token acts with your account's permissions; a scope does not grant access
to projects you cannot already read. Organization policies can restrict PAT
creation or use. Consult your administrator instead of broadening permissions.
See [Microsoft's PAT guidance](https://learn.microsoft.com/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops).

This token authenticates the collector's **Azure Boards REST requests**. It does
not configure Git authentication for clone, pull or push against Azure Repos.

### Windows: Persistent User Environment

1. Open **Edit environment variables for your account** from Windows Search.
2. Under **User variables**, create `COPILOT_ADO_PAT` with your token as its value.
   Prefer user scope over a machine-wide system variable. No administrator
   access is needed for user scope.
3. Close all VS Code windows and processes, then reopen VS Code. Existing
   terminals and editor processes do not automatically inherit new variables.
   If a newly launched process still has the old environment, sign out and back in.

Do not use a command containing the literal token, such as `setx` with the token
as an argument: it can remain in command history. Do not share screenshots of
the variable editor. Persistent environment variables are **not a secret vault**.

### PowerShell 7: Current Session Only

This alternative works in PowerShell 7 on Windows, Linux and macOS. Run it
yourself in a terminal, not through the agent. The prompt masks input and keeps
the literal token out of command history:

```powershell
$pat = Read-Host 'Azure DevOps PAT' -AsSecureString
try {
    $env:COPILOT_ADO_PAT = [System.Net.NetworkCredential]::new('', $pat).Password
}
finally {
    $pat.Dispose()
    Remove-Variable pat
}
```

The environment value is still plaintext in the process. This does not persist
it for future sessions. Launch VS Code from this configured terminal with
`code .` in your target repository, after closing existing VS Code processes.
Otherwise the launcher may reuse a process with the old environment. Setting a
variable in an integrated terminal does not update the parent editor or other
agent terminals.

### Linux/macOS: Current Shell Only

Run the snippet for your shell yourself, with shell tracing disabled. Do not
paste a literal token into a shell profile or an `export` command.

Bash:

```bash
read -r -s -p 'Azure DevOps PAT: ' COPILOT_ADO_PAT
printf '\n'
export COPILOT_ADO_PAT
```

Zsh (the default interactive shell on recent macOS versions):

```zsh
read -r -s 'COPILOT_ADO_PAT?Azure DevOps PAT: '
printf '\n'
export COPILOT_ADO_PAT
```

Close existing VS Code processes, then launch `code .` from this shell in the
target repository. These settings last only for this shell and its child
processes. For persistent use, follow your team's approved secret-management
method to inject the variable at launch; do not store the PAT in startup files.

### Verify Without Revealing the Token

Run these commands in the same execution environment the agent will use. They
print the PowerShell version and a Boolean, never the token:

```text
pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
pwsh -NoLogo -NoProfile -Command '[bool]$env:COPILOT_ADO_PAT'
```

These commands work in PowerShell, Bash and Zsh. Expect version 7 or later and
`True`. Presence alone does not prove that the token is valid or authorized.
Do not dump environment variables or authentication headers for troubleshooting.

For WSL, Remote SSH or dev containers, configure the variable **inside the
environment where the collector runs**. A Windows user variable is not
automatically available in these environments. Environment values are inherited
by child processes and may be accessible to tools running as your user.

Rotate tokens before expiry and revoke unused or exposed tokens in Azure DevOps.
After replacement, update the variable and restart the relevant processes.
Removing a local variable does not revoke the token or erase inherited copies.

## Keep Task Data Local

Before the first capture, exclude `/.aw/tasks/` in the **consuming repository**.
For a local-only rule, add the following line to that repository's Git exclude
file (normally `.git/info/exclude`; `git rev-parse --git-path info/exclude` locates
it for worktrees too):

```gitignore
/.aw/tasks/
```

Alternatively, agree with your team to add that rule to the repository's root
`.gitignore`. Do not ignore all of `.aw/`: non-secret configuration and other
workflow documents may legitimately be shared. The skill's bundled
[.gitignore](./.gitignore) protects files beneath its own location, **not** task
output elsewhere in a consuming repository. The skill does not edit your Git
configuration or exclusions automatically.

Verify the rule from the consuming repository with
`git check-ignore -v .aw/tasks/42/source.json` (a synthetic path; no file needed).
Ignore rules do not remove already tracked files or erase Git history. Check
`git ls-files -- .aw/tasks/` before assuming existing captures are private.

Snapshots preserve original fields, comments, names, links and attachments. They
may contain confidential information or secrets already present in the Board;
there is **no automatic redaction**. Never store the authentication PAT in task
files, YAML configuration, `.env` files, examples or commits. Review both staged
and untracked content before publishing. Git exclusions do not protect against
backups, cloud sync or sending content to an AI service: follow your organization's
data and agent-use policies.

## Use the Skill

Start with a full URL; it requires no organization/project configuration:

```text
/ado-task-context https://dev.azure.com/example/Project%20One/_workitems/edit/42
```

Or ask: "Use ado-task-context to read this Azure Boards task and prepare context
for this repository: <full work-item URL>. Do not implement it."

Replace the synthetic URL with your work item. Legacy URLs of the form
`https://example.visualstudio.com/Project%20One/_workitems/edit/42` are also
accepted. Use HTTPS and the actual organization/project; do not infer them from
the Git repository name.

For repeated ID-only requests, optionally configure `.aw/config.yaml` in the
consuming repository, preserving any other existing settings:

```yaml
ado:
  organization: example
  project: Project One
```

Then request `/ado-task-context 42`. **The agent reads this YAML**, not the
collector. No YAML PowerShell module is required by the collector. Explicit URL
values take precedence. Missing or ambiguous settings result in a request for
the full URL, not a guessed organization. Do not put credentials in this file.

### Direct Collector Use

For capture-only troubleshooting, run from the consuming repository. Replace
the script path with your installation path. Both examples work in PowerShell,
Bash and Zsh; quoted paths support spaces:

```text
pwsh -NoLogo -NoProfile -File "/path/to/ado-task-context/scripts/collect-task.ps1" -WorkItem "https://dev.azure.com/example/Project%20One/_workitems/edit/42" -Root "."
pwsh -NoLogo -NoProfile -File "/path/to/ado-task-context/scripts/collect-task.ps1" -WorkItem "42" -Org "example" -Project "Project One" -Root "."
```

On Windows, use a Windows script path. `-Root` identifies the repository receiving
the output, not the skill folder. For an ID, the CLI requires explicit `-Org`
and `-Project`; it does not read `.aw/config.yaml`. Direct execution creates no
`context.md` and does not review code or attachments.

## Output and Refresh

```text
<consuming repository>/.aw/tasks/<id>/
  source.md
  source.json
  context.md
  attachments/
```

| Output         | Ownership and purpose                                                              |
| -------------- | ---------------------------------------------------------------------------------- |
| `source.md`    | Collector-owned evidence, including original rich-text HTML. Do not edit.          |
| `source.json`  | Collector-owned structured snapshot, revision, evidence hashes and warnings.       |
| `context.md`   | Agent-reviewed requirements, repository references, questions and human decisions. |
| `attachments/` | Downloaded evidence. Downloaded does not mean reviewed.                            |

The agent uses the [context template](./assets/context-template.md). Capture
status `Captured; review pending` is not approval to implement. The final context
is `Ready for planning`, `Needs clarification` or `Partial capture`; readiness
does not claim that acceptance tests pass. Relevant unread evidence remains a
blocker. Source wording is preserved; context follows repository language rules
(English by default), while conversation defaults to Spanish unless requested
otherwise.

Ask the agent to refresh the same task to capture changes and update affected
analysis. The collector never writes `context.md`. The agent must preserve
requirement IDs, human notes and confirmed decisions, marking conflicts for
reconfirmation. Failed work-item retrieval leaves the previous snapshot stale
but retained. Partial captures carry warnings and must not be called complete.
Old attachments are not automatically deleted. Different organizations/projects
using the same task ID in one output root are rejected rather than overwritten.

### Limits and Safety

- 25 MiB per attachment, 200 MiB of accepted attachment data per run, and 100
  download candidates.
- 100 comment pages, 16 MiB per JSON response and a 60-second timeout per HTTP
  request.
- These limits are fixed in the scripts; there are no CLI override switches.
  Changing them requires a separate maintenance decision, not an automatic retry.
- Credentialed requests stay within the verified Azure organization; HTTP
  redirects are not followed. External downloads require explicit approval and
  must not receive the PAT.
- Board text and attachments are untrusted evidence, not agent instructions.
  Downloads are not executed, archives are not automatically unpacked, and
  missing readers are reported rather than installed.

## Troubleshooting

| Symptom                                          | Check                                                                                                                                    |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `pwsh` not found or version below 7              | Install PowerShell 7 using the official OS instructions and ensure it is on the execution environment's PATH.                            |
| `COPILOT_ADO_PAT is missing`                     | Check presence without printing it; restart VS Code and check remote/container environment inheritance.                                  |
| HTTP 401                                         | Check token value, expiry, revocation and organization. Never post the token in an issue.                                                |
| HTTP 403                                         | Check Work Items Read scope, account/project permissions and organization policies.                                                      |
| HTTP 404                                         | Verify the full URL, project and visibility. A 404 alone does not prove the task does not exist.                                         |
| Redirect or non-JSON response                    | Verify the canonical supported work-item URL and authentication. Do not enable credential forwarding to redirects.                       |
| Timeout or connectivity failure                  | Check proxy/network access and retry when connectivity is restored; report retained evidence as stale.                                   |
| Partial capture                                  | Inspect source warnings for failed comments, blocked URLs or size/page limits. Resolve missing evidence before declaring readiness.      |
| Attachment downloaded but unread                 | Use an already available safe reader or record the limitation and relevance. Download is not review.                                     |
| Existing source has a different target/generator | Verify the intended repository and task; preserve the files and resolve the conflict explicitly. Do not delete them to bypass the check. |

## Maintenance and Publication

From the skill folder, run the existing offline checks:

```text
pwsh -NoLogo -NoProfile -File ./scripts/test-collector.ps1
```

Expect two `PASS:` messages. The tests use synthetic responses and a temporary
directory, clean up their output, and require neither a PAT nor network access.
They cover target resolution, URL boundaries, pagination, attachment inventory,
partial capture, refresh and preservation. They mock the HTTP request function:
passing them does not validate live authentication, all transport/limit cases or
every operating system.

Before sharing a release:

- Run offline checks and review documentation links and CLI examples. Record
  which platforms were actually tested.
- Review staged changes and untracked files for tokens and private Board data;
  use synthetic examples in documentation, tests and issue reports.
- Choose an appropriate license before offering public reuse. This guide does
  not grant a license on its own.
- Tag releases and record compatibility or breaking changes. Preserve local
  task evidence when upgrading; do not assume snapshots from a different
  generator version can be refreshed without migration.
- Keep each skill bundle self-contained when organizing a collection by usage.
  Update one installed copy deliberately and avoid duplicate active versions.
- Consider HTTP-layer tests and CI before broader distribution. Any live smoke
  test belongs in an authorized private repository, with the user's own token
  configured outside chat and task outputs excluded from Git.
