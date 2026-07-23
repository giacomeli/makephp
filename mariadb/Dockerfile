# 12.2: mesma serie que inicializou o volume de dados existente (downgrade nao sobe)
FROM mariadb:12.2

# Timezone configurável no build (TZ do .env é repassada pelo compose)
ARG TZ=UTC
ENV TZ=${TZ}
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Configuração personalizada (tuning de InnoDB, conexões e slow log)
COPY my.cnf /etc/mysql/conf.d/my.cnf

# Permissões: 644 apenas nos arquivos (o diretório precisa manter o bit x)
RUN find /etc/mysql/conf.d/ -type f -exec chmod 644 {} +

# Scripts de inicialização entram por bind mount em /docker-entrypoint-initdb.d
# (ver docker-compose.yml) — nada de dados no build da imagem.

CMD ["mariadbd"]

EXPOSE 3306
