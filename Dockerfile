# Build stage - compile Traccar from source
FROM eclipse-temurin:17-jdk AS builder

WORKDIR /build

# Copy Gradle wrapper and build files first (for better caching)
COPY gradlew gradlew.bat ./
COPY gradle ./gradle
COPY build.gradle settings.gradle ./

# Download dependencies (cached if build files don't change)
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon || true

# Copy source code
COPY src ./src
COPY schema ./schema
COPY templates ./templates

# Build the application
RUN ./gradlew assemble --no-daemon

# Runtime stage - minimal image
FROM eclipse-temurin:17-jre

WORKDIR /opt/traccar

# Create necessary directories
RUN mkdir -p /opt/traccar/logs /opt/traccar/data

# Copy built artifacts from builder
COPY --from=builder /build/target/tracker-server.jar ./tracker-server.jar
COPY --from=builder /build/target/lib ./lib

# Copy configuration templates
COPY --from=builder /build/schema ./schema
COPY --from=builder /build/templates ./templates

# Copy default configuration (can be overridden by environment variables)
COPY setup/traccar.xml /opt/traccar/conf/traccar.xml

# Expose ports
# 8082 - Web UI and REST API
# 5000-5150 - Device protocols
EXPOSE 8082 5000-5150

# Default environment variables (can be overridden at runtime)
ENV CONFIG_USE_ENVIRONMENT_VARIABLES="true" \
    DATABASE_DRIVER="org.postgresql.Driver" \
    DATABASE_URL="jdbc:postgresql://aws-0-us-west-2.pooler.supabase.com:6543/postgres?pgbouncer=true" \
    DATABASE_USER="postgres.xspkeynlexpiyjzzoyul" \
    DATABASE_PASSWORD="0b9r!hUz2&IZ" \
    OSMAND_PORT="5055" \
    GPS103_PORT="5001"

# Health check
HEALTHCHECK --interval=2m --timeout=5s --start-period=60s --retries=3 \
    CMD wget -q --spider http://localhost:8082/api/health || exit 1

# Run Traccar
ENTRYPOINT ["java", "-Xms1g", "-Xmx1g", "-jar", "tracker-server.jar", "conf/traccar.xml"]
