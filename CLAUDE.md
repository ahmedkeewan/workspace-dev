# workspace-dev — agent rules

@README.md

- Start services with `dev up <svcs> --json` and read URLs from its output. Never assume a
  port: another workspace may hold slot 0.
- `dev up` blocks until healthy and exits non-zero with the failing service's logs. Don't
  poll or sleep around it.
- Run `dev down` when you're done, to free the slot (max 3 per machine).
- Destructive commands need `--yes` (`dev reset --yes`); there are no interactive prompts.
- Before saying something can't run, check `dev doctor --json`.
- Logs: `dev logs <svc> -n 100` (no `-f` in agent runs, since it never exits).

## Editing this repo

- `bin/dev`: the CLI (bash 3.2-compatible, since macOS ships it). `libexec/run`: per-service
  start logic. `process-compose.yaml`: dependency graph + health checks only, no logic.
- Adding a service: a line in `ports.txt`, a case in `libexec/run`, an entry in
  `process-compose.yaml`. Adding a store: `compose.stores.yaml` + `ports.txt` + `CONTAINERS`
  in `dev.conf` + a container-logs entry in `process-compose.yaml`. Adding a repo: `repos.txt`.
- Run `tests/test.sh` after touching `bin/dev`.
