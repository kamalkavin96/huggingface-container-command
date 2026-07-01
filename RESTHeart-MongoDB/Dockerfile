# Pull the official RestHeart image just to grab its files
FROM softinstigate/restheart:latest AS restheart

# RestHeart 9.x requires Java 25 (GraalVM-based) — using an older JRE
# throws: UnsupportedClassVersionError (class file version 69.0 vs 65.0)
FROM eclipse-temurin:25-jre-jammy

# Install MongoDB 7.0
RUN apt-get update && apt-get install -y --no-install-recommends gnupg curl \
    && curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] http://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
       > /etc/apt/sources.list.d/mongodb-org-7.0.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends mongodb-org \
    && rm -rf /var/lib/apt/lists/*

# Bring in RestHeart (jar + plugins + default config)
COPY --from=restheart /opt/restheart /opt/restheart
WORKDIR /opt/restheart

RUN mkdir -p /data/db

COPY start.sh /start.sh
RUN chmod +x /start.sh

ENV RHO="/http-listener/host->'0.0.0.0';/http-listener/port->7860;/mclient/connection-string->'mongodb://127.0.0.1:27017'"

EXPOSE 7860

CMD ["/start.sh"]