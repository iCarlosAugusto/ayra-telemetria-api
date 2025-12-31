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

# Frontend build stage
FROM node:20-alpine AS frontend

WORKDIR /app

# Copy frontend source
COPY traccar-web/package*.json ./
RUN npm install --legacy-peer-deps

COPY traccar-web/ ./
RUN npm run build

# Runtime stage - minimal image
FROM eclipse-temurin:17-jre

WORKDIR /opt/traccar

# Create necessary directories
RUN mkdir -p /opt/traccar/logs /opt/traccar/data /opt/traccar/web

# Copy built artifacts from builder
COPY --from=builder /build/target/tracker-server.jar ./tracker-server.jar
COPY --from=builder /build/target/lib ./lib

# Copy configuration templates
COPY --from=builder /build/schema ./schema
COPY --from=builder /build/templates ./templates

# Copy built frontend (vite.config.js: outDir: 'build')
COPY --from=frontend /app/build ./web

# Copy default configuration (can be overridden by environment variables)
COPY setup/traccar.xml /opt/traccar/conf/traccar.xml

# Expose ports
# 8082 - Web UI and REST API
# 5000-5150 - Device protocols
EXPOSE 8082 5000-5150

# Default environment variables (can be overridden at runtime)
# WEB_PORT uses Render's PORT env var, defaulting to 8082 for local development
ENV CONFIG_USE_ENVIRONMENT_VARIABLES="true" \
    DATABASE_DRIVER="org.postgresql.Driver" \
    DATABASE_URL="jdbc:postgresql://aws-0-us-west-2.pooler.supabase.com:6543/postgres?pgbouncer=true&prepareThreshold=0" \
    DATABASE_USER="postgres.xspkeynlexpiyjzzoyul" \
    DATABASE_PASSWORD="0b9r!hUz2&IZ" \
    OSMAND_PORT="5055" \
    GPS103_PORT="5001" \
    WEB_PORT="8082"

# Health check - uses WEB_PORT for dynamic port checking
HEALTHCHECK --interval=2m --timeout=5s --start-period=60s --retries=3 \
    CMD wget -q --spider http://localhost:${WEB_PORT:-8082}/api/health || exit 1

# Run Traccar
# Use shell form to allow environment variable expansion for Render's PORT
CMD WEB_PORT=${PORT:-8082} && exec java -Xms512m -Xmx512m -jar tracker-server.jar conf/traccar.xml