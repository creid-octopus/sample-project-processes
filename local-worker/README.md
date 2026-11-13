# Local worker

A polling Tentacle container that registers as a worker in the `Local Container` pool of the `multi-tenant-testing` space. Terraform creates the pool. This container fills it.

## Start

```bash
cd local-worker
cp .env.example .env                 # then edit .env
uuidgen | tr -d '-' | tr 'A-Z' 'a-z' > worker-machine-id
mkdir -p worker-applications
docker compose up -d
docker compose logs -f worker        # look for a successful registration
```

The worker should show **Healthy** under Infrastructure, Workers, in the space.

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | The worker service. |
| `.env.example` | Settings to copy into `.env`. `.env` is gitignored. |
| `worker-machine-id` | You generate it once. Pins the machine ID so image updates can still decrypt the stored configuration. Gitignored. |
| `worker-applications/` | Extracted packages, kept on the host so they survive container recreates. Gitignored. |

## What persists

| Item | Where | Survives `docker compose down` | Survives `down -v` |
|---|---|---|---|
| Registration and identity | `worker-config` volume | Yes | No |
| Machine ID | `worker-machine-id` file | Yes | Yes |
| Extracted packages | `worker-applications/` folder | Yes | Yes |

After `down -v` the worker registers again. If a worker with the same name already exists, delete it in the UI first, or set a new `WORKER_NAME`.

## Notes

* The API key needs permission to register workers in the space. A key for the Terraform agent identity should not have it, so use your own short-lived key.
* The `Space` setting is how the container chooses a space other than the default. Check the registration log if the worker lands in the wrong space.
* Docker-in-Docker is off, because the mock steps are plain bash. Turn it on (`DISABLE_DIND=N`, plus `privileged: true`) only if you add steps that run containers.
* The image is amd64 only. On Apple silicon it runs emulated.

## After the worker is healthy

1. In `terraform/`, set `target_worker_pool_name` to `Local Container` and apply.
2. In the definition JSON, add `"workerPool": "local-container"`, regenerate, and push.
