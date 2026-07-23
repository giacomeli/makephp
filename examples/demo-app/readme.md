# demo-app

Minimal PHP application (no framework) used to validate the makephp stack and
to serve as the structural template for registering real applications.

The same code demonstrates the three nginx integration modes:

| Mode | How | What it validates |
| --- | --- | --- |
| `proxy` | Own container running `php -S` under supervisord | register-app, build-app, reverse proxy |
| `php` | Served by the shared php-fpm | FastCGI, vhost generation with the right root |
| `html` | Static `public/index.html` | Static file serving |

## Running it

```bash
# The DEMO_APP_* block ships in .env.example. From the repository root:
make register-app demo-app
make build-app demo-app
make up demo-app
curl --resolve demo-app.test:8099:127.0.0.1 "http://demo-app.test:8099/?format=json"
```

Or run the full three-mode validation with `make smoke`.

## Layout

- `public/index.php` — status page: PHP version, loaded extensions and (when
  the `DB_HOST`/`REDIS_HOST` envs exist) MariaDB and Redis connectivity.
  `?format=json` returns JSON (used by the smoke test).
- `container_config/` — the contract every registered application needs:
  `Dockerfile` (based on the makephp base image), `entrypoint.sh` and
  `supervisord.conf` (the app processes).
