# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jre-jammy

ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser

# Elastic APM agent
ADD --chmod=0644 https://repo1.maven.org/maven2/co/elastic/apm/elastic-apm-agent/1.55.4/elastic-apm-agent-1.55.4.jar /opt/elastic-apm-agent.jar

# APM: agent loaded via JAVA_TOOL_OPTIONS, ENABLED/ENVIRONMENT computed by entrypoint.sh
ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/elastic-apm-agent.jar" \
    ELASTIC_APM_SERVER_URLS="https://ellarea-apm.innov-ds.com" \
    ELASTIC_APM_APPLICATION_PACKAGES="com.ids"

COPY --chmod=0755 entrypoint.sh /entrypoint.sh

USER appuser

ENTRYPOINT ["/entrypoint.sh"]
CMD ["java", "org.springframework.boot.loader.launch.JarLauncher"]
