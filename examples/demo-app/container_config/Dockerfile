# Imagem do demo-app: parte da imagem base do makephp.
# Local: builde a base antes (make build) e tagueie, ou use a publicada.
ARG BASE_IMAGE=giacomeli/makephp:8.3-dev
FROM ${BASE_IMAGE}

COPY container_config/supervisord.conf /etc/supervisor/conf.d/demo-app.conf
COPY container_config/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /var/www
EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
