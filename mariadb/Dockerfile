# 12.2: same series that initialized the existing data volume (a downgrade will not boot)
FROM mariadb:12.2

# Timezone configurable at build time (TZ from .env is forwarded by compose)
ARG TZ=UTC
ENV TZ=${TZ}
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Custom configuration (InnoDB tuning, connections and slow log)
COPY my.cnf /etc/mysql/conf.d/my.cnf

# Permissions: 644 on files only (the directory needs to keep its x bit)
RUN find /etc/mysql/conf.d/ -type f -exec chmod 644 {} +

# Init scripts come in through a bind mount at /docker-entrypoint-initdb.d
# (see docker-compose.yml) — no data baked into the image.

CMD ["mariadbd"]

EXPOSE 3306
