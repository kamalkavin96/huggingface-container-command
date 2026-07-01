FROM quay.io/keycloak/keycloak:26.4 AS builder
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_CACHE=local
ENV KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.4
COPY --from=builder /opt/keycloak/ /opt/keycloak/
ENV KC_HTTP_PORT=7860
ENV KC_HTTP_ENABLED=true
ENV KC_HOSTNAME=https://iam-service-server.hf.space
ENV KC_PROXY_HEADERS=xforwarded
ENV KC_PROXY=edge
EXPOSE 7860
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized"]
