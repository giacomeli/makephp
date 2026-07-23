# demo-app

Aplicacao PHP minima (sem framework) usada para validar a stack do makephp e
servir de modelo estrutural para registrar aplicacoes reais.

O mesmo codigo demonstra os tres modos de integracao com o nginx:

| Modo | Como | O que valida |
| --- | --- | --- |
| `proxy` | Container proprio rodando `php -S` via supervisord | register-app, build-app, proxy reverso |
| `php` | Servido pelo php-fpm compartilhado | FastCGI, geracao de vhost com root correto |
| `html` | `public/index.html` estatico | Serving de estaticos |

## Como rodar

```bash
# O bloco DEMO_APP_* ja vem no .env.example. Na raiz do repositorio:
make register-app demo-app
make build-app demo-app
make up demo-app
curl --resolve demo-app.test:8099:127.0.0.1 "http://demo-app.test:8099/?format=json"
```

Ou rode a validacao completa dos tres modos com `make smoke`.

## Estrutura

- `public/index.php` — pagina de status: versao do PHP, extensoes carregadas e
  (quando as envs `DB_HOST`/`REDIS_HOST` existem) conectividade com MariaDB e
  Redis. `?format=json` retorna JSON (usado pelo smoke test).
- `container_config/` — o contrato que toda aplicacao registrada precisa ter:
  `Dockerfile` (parte da imagem base do makephp), `entrypoint.sh` e
  `supervisord.conf` (processos do app).
