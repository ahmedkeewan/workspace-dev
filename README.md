# workspace-dev

A template for a one-command local dev environment across several repos, in the spirit of
GitHub's [Scripts to Rule Them All](https://github.blog/engineering/scripts-to-rule-them-all/)
and Shopify's `dev`: new people (and coding agents) clone one repo, run one script, and
`dev up web` starts the whole stack with its dependencies, health-checked, on ports that
never collide with a second checkout.

Why it's shaped this way: [Making your dev environment work for AI agents](https://dev-env-for-agents.pastehtml.dev/)
(a field guide; a copy is in [docs/dev-env-for-agents.html](docs/dev-env-for-agents.html)) and the
talk version, [docs/agent-sandbox-vs-dev-env.pptx](docs/agent-sandbox-vs-dev-env.pptx).

Plain bash (3.2, so stock macOS works), [process-compose](https://github.com/F1bonacc1/process-compose)
for the service graph, Docker Compose for the stores, [mise](https://mise.jdx.dev) for pinned
toolchains. No daemon, nothing to install into your repos.

## What you get

- **`bootstrap.sh`**: idempotent setup: Homebrew/apt tools, the pinned toolchain, clones every
  repo in `repos.txt` next to this one, installs each repo's deps, points their git hooks at a
  shared `hooks/` (gitleaks pre-commit), creates a personal secrets file, puts `dev` on PATH.
- **`dev up <svc...>`**: starts the services plus everything they depend on, blocks until every
  health check passes, prints URLs, detaches. Fails non-zero with the failing service's logs.
- **Slots**: up to 3 stacks per machine (parallel worktrees, agents). Each workspace claims a
  slot on `up`; every port shifts by `10 × slot` and each slot has its own Docker volumes.
- **Agent-friendly**: no prompts (destructive commands need `--yes`), `--json` on everything that
  reports state, and a `CLAUDE.md` with the rules.
- `dev status`, `dev logs`, `dev attach` (TUI), `dev seed`, `dev reset --yes`, `dev update`
  (fast-forward clean repos only), `dev doctor` (what's missing and what breaks without it).

## Try it

The template ships with an example stack (Postgres + two tiny Python servers), so it runs as is:

```sh
mkdir acme && cd acme
git clone https://github.com/ahmedkeewan/workspace-dev && ./workspace-dev/bootstrap.sh
dev up web        # postgres → seed → api → web
dev status
dev down
```

Needs macOS or Linux/WSL2 and a Docker runtime (bootstrap installs Colima if you have none).

## Make it yours

1. **`dev.conf`**: your project's `NAME`, GitHub owner, and the CLI's name (keep `dev`, or pick
   something unique if you use this template for more than one project).
2. **`repos.txt`**: one line per repo: name, branch, install command. Rename this repo's line.
3. **`ports.txt`**: one line per service and store with its slot-0 port; `bin/dev` exports
   `PORT_<NAME>` for each.
4. **`libexec/run`**: one case per service: `cd` into its repo, set its env, `exec` it.
5. **`process-compose.yaml`**: the dependency graph and readiness probes. No logic here.
6. **`compose.stores.yaml`**: your databases, each with a healthcheck; list them in
   `CONTAINERS` in `dev.conf` and give each a log entry in `process-compose.yaml`.
7. **`seed`** in `libexec/run`: how to fill an empty slot with test data.
8. **`secrets.env.example`**: every key people may need, with a `# what breaks without it`
   comment; `dev doctor` shows that comment for each one that's missing.
9. **`mise.toml`**: your runtimes (python, node, …), **`Brewfile`**: system tools.
10. **`CLAUDE.md`**: the agent rules, with your services and test login.

Then `tests/test.sh` (no Docker needed) and a real `dev up`.

## Layout

One folder holds this repo and the repos it runs, side by side. That folder is the
**workspace**; each one gets its own slot.

```
acme/                         # the workspace (any folder name)
├── workspace-dev/            # this repo: clone it first
│   ├── bootstrap.sh          # one-time setup, safe to re-run
│   ├── bin/dev               # the CLI
│   ├── dev.conf              # project name, CLI name, GitHub owner, slots
│   ├── repos.txt             # repos to clone, with branch + install command
│   ├── ports.txt             # each service's port
│   ├── libexec/run           # how each service starts
│   ├── process-compose.yaml  # what depends on what, health checks
│   ├── compose.stores.yaml   # databases (Docker)
│   ├── mise.toml, Brewfile   # pinned tools
│   ├── secrets.env.example   # keys people may need
│   └── hooks/  tests/  docs/
├── acme-api/                 # your repos, cloned here by bootstrap.sh
└── acme-web/

~/.acme-dev/                  # per machine, outside every repo
├── secrets.env               # your keys (never committed)
├── slots/                    # which workspace holds which slot
└── state/<slot>/             # per-slot state
```

## Notes

- Store ports should stay below 32768. Higher ones sit in the OS ephemeral range, and a random
  outgoing connection (Docker's own port forwarding, for one) can take them.
- Vite and Node dev servers: bind to `127.0.0.1` (`--host 127.0.0.1`), or Node may listen on
  `::1` only and health checks against 127.0.0.1 fail.
- Two projects using this template on one machine need different `PC_BASE_PORT`s and app ports.
- Docker runtimes: Colima is free (MIT); OrbStack and Docker Desktop need paid seats for
  most commercial use. Podman's compose support (`--wait`, healthchecks) is uneven.

## Contributing

Issues and PRs welcome. Run `tests/test.sh` and a real `dev up web` before sending one.

MIT licensed; see [LICENSE](LICENSE).
