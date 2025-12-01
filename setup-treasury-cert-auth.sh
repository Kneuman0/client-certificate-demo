#!/bin/bash

# Treasury Certificate Authentication Demo Setup Script
# This script automates the complete setup for Linux/macOS environments

set -euo pipefail

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

write_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

write_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

write_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

write_error() {
    echo -e "${RED}❌ $1${NC}"
}

write_step() {
    echo -e "\n${MAGENTA}🔧 Step $1: $2${NC}"
    echo -e "${GRAY}------------------------------------------------${NC}"
}

# Default values
JAVA_HOME="${JAVA_HOME:-}"
SKIP_MKCERT="${SKIP_MKCERT:-false}"
BUILD_ONLY="${BUILD_ONLY:-false}"

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --java-home)
                JAVA_HOME="$2"
                shift 2
                ;;
            --skip-mkcert)
                SKIP_MKCERT="true"
                shift
                ;;
            --build-only)
                BUILD_ONLY="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                write_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to show help
show_help() {
    cat << EOF
Treasury Certificate Authentication Demo Setup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --java-home PATH     Path to Java installation (auto-detected if not specified)
    --skip-mkcert        Skip mkcert installation if already installed
    --build-only         Only build the project, don't start the server
    -h, --help          Show this help message

EXAMPLES:
    $0
    $0 --java-home /usr/lib/jvm/java-17-openjdk
    $0 --build-only

EOF
}

# Function to find Java installation
find_java_installation() {
    write_info "Detecting Java installation..."
    
    if [[ -n "$JAVA_HOME" ]]; then
        if [[ -f "$JAVA_HOME/bin/keytool" ]]; then
            write_success "Java found at: $JAVA_HOME"
            return 0
        else
            write_error "Java not found at $JAVA_HOME"
            exit 1
        fi
    fi
    
    # Try common Java locations
    local java_paths=(
        "/usr/lib/jvm/java-17-openjdk"
        "/usr/lib/jvm/java-17-openjdk-amd64"
        "/usr/lib/jvm/temurin-17-jdk-amd64"
        "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
        "/System/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home"
        "$HOME/.sdkman/candidates/java/current"
    )
    
    for path in "${java_paths[@]}"; do
        if [[ -f "$path/bin/keytool" ]]; then
            JAVA_HOME="$path"
            write_success "Java found at: $JAVA_HOME"
            return 0
        fi
    done
    
    # Try using which command
    if command -v java >/dev/null 2>&1; then
        local java_path=$(readlink -f $(which java))
        JAVA_HOME=$(dirname $(dirname $java_path))
        if [[ -f "$JAVA_HOME/bin/keytool" ]]; then
            write_success "Java found at: $JAVA_HOME"
            return 0
        fi
    fi
    
    write_error "Java installation not found. Please set JAVA_HOME environment variable or use --java-home parameter"
    exit 1
}

# Function to install mkcert
install_mkcert_tool() {
    write_info "Installing mkcert..."
    
    if command -v mkcert >/dev/null 2>&1; then
        if [[ "$SKIP_MKCERT" == "false" ]]; then
            write_warning "mkcert is already installed. Use --skip-mkcert to skip reinstallation."
        fi
        return 0
    fi
    
    # Check for package managers
    if command -v brew >/dev/null 2>&1; then
        write_info "Installing mkcert via Homebrew..."
        brew install mkcert nss
    elif command -v apt >/dev/null 2>&1; then
        write_info "Installing mkcert via apt..."
        sudo apt update
        sudo apt install -y mkcert libnss3-tools
    elif command -v yum >/dev/null 2>&1; then
        write_info "Installing mkcert via yum..."
        sudo yum install -y mkcert nss-tools
    elif command -v pacman >/dev/null 2>&1; then
        write_info "Installing mkcert via pacman..."
        sudo pacman -S mkcert
    else
        write_error "No supported package manager found. Please install mkcert manually."
        write_info "Visit: https://github.com/FiloSottile/mkcert"
        exit 1
    fi
    
    # Verify installation
    if command -v mkcert >/dev/null 2>&1; then
        write_success "mkcert installed successfully"
    else
        write_error "mkcert installation failed"
        exit 1
    fi
}

# Function to setup local CA
setup_local_ca() {
    write_info "Setting up local Certificate Authority..."
    
    export JAVA_HOME="$JAVA_HOME"
    
    if ! mkcert -install; then
        write_error "Failed to setup local CA"
        exit 1
    fi
    
    write_success "Local CA installed successfully"
}

# Function to install CA into Java trust store
install_ca_into_java() {
    write_info "Installing CA into Java trust store..."
    
    local keytool_path="$JAVA_HOME/bin/keytool"
    local ca_cert_path="$HOME/.local/share/mkcert/rootCA.pem"
    
    if [[ ! -f "$ca_cert_path" ]]; then
        write_error "mkcert CA certificate not found at $ca_cert_path"
        exit 1
    fi
    
    # Check if already installed
    if "$keytool_path" -list -cacerts -alias "mkcert-local-ca" -storepass changeit >/dev/null 2>&1; then
        write_warning "mkcert CA is already installed in Java trust store"
        return 0
    fi
    
    # Install CA certificate
    if ! "$keytool_path" -importcert -storepass changeit -noprompt -trustcacerts -alias "mkcert-local-ca" -cacerts -file "$ca_cert_path"; then
        write_error "Failed to import CA certificate into Java trust store"
        write_info "You may need to run this with sudo or as root"
        exit 1
    fi
    
    write_success "CA certificate installed into Java trust store"
}

# Function to create server keystore
create_server_keystore() {
    write_info "Creating server keystore..."
    
    local keystore_path="src/main/resources/server-keystore.p12"
    
    if [[ -f "$keystore_path" ]]; then
        write_warning "Server keystore already exists. Skipping creation."
        return 0
    fi
    
    # Create server keystore
    if ! mkcert -p12-file server-keystore.p12 -pkcs12 localhost mydev.local; then
        write_error "Failed to create server keystore"
        exit 1
    fi
    
    # Move to resources directory if created in current directory
    if [[ -f "server-keystore.p12" ]]; then
        mv server-keystore.p12 "$keystore_path"
    fi
    
    write_success "Server keystore created at: $keystore_path"
}

# Function to create Treasury trust store
create_treasury_trust_store() {
    write_info "Creating Treasury trust store..."
    
    local keytool_path="$JAVA_HOME/bin/keytool"
    local trust_store_path="src/main/resources/treasury-truststore.p12"
    local root_cert_path="src/main/resources/Treasury-Root-CA.cer"
    local ocio_cert_path="src/main/resources/Treasury-OCIO-CA.cer"
    local mkcert_ca_path="$HOME/.local/share/mkcert/rootCA.pem"
    
    # Check if Treasury certificates exist
    if [[ ! -f "$root_cert_path" ]]; then
        write_error "Treasury Root CA certificate not found at $root_cert_path"
        exit 1
    fi
    
    if [[ ! -f "$ocio_cert_path" ]]; then
        write_error "Treasury OCIO CA certificate not found at $ocio_cert_path"
        exit 1
    fi
    
    # Remove existing trust store if it exists
    if [[ -f "$trust_store_path" ]]; then
        rm -f "$trust_store_path"
        write_info "Removed existing Treasury trust store"
    fi
    
    # Import Treasury Root CA
    if ! "$keytool_path" -importcert -storepass changeit -noprompt -trustcacerts -alias "treasury-root-ca" -keystore "$trust_store_path" -storetype PKCS12 -file "$root_cert_path"; then
        write_error "Failed to import Treasury Root CA"
        exit 1
    fi
    
    # Import Treasury OCIO CA
    if ! "$keytool_path" -importcert -storepass changeit -noprompt -trustcacerts -alias "treasury-ocio-ca" -keystore "$trust_store_path" -storetype PKCS12 -file "$ocio_cert_path"; then
        write_error "Failed to import Treasury OCIO CA"
        exit 1
    fi
    
    # Import mkcert CA for testing
    if [[ -f "$mkcert_ca_path" ]]; then
        if "$keytool_path" -importcert -storepass changeit -noprompt -trustcacerts -alias "mkcert-ca" -keystore "$trust_store_path" -storetype PKCS12 -file "$mkcert_ca_path"; then
            write_info "mkcert CA imported for testing"
        else
            write_warning "Failed to import mkcert CA (non-critical)"
        fi
    fi
    
    write_success "Treasury trust store created at: $trust_store_path"
}

# Function to update application.properties
update_application_properties() {
    write_info "Updating application.properties..."
    
    local properties_path="src/main/resources/application.properties"
    
    if [[ ! -f "$properties_path" ]]; then
        write_error "application.properties not found"
        exit 1
    fi
    
    # Create backup
    cp "$properties_path" "$properties_path.backup"
    
    # Update properties using sed
    sed -i.tmp 's|^server\.ssl\.trust-store=.*|server.ssl.trust-store=classpath:treasury-truststore.p12|g' "$properties_path"
    sed -i.tmp 's|^server\.ssl\.trust-store-type=.*|server.ssl.trust-store-type=PKCS12|g' "$properties_path"
    sed -i.tmp 's|^server\.ssl\.client-auth=.*|server.ssl.client-auth=need|g' "$properties_path"
    
    # Add missing properties
    if ! grep -q "server.ssl.trust-store=" "$properties_path"; then
        echo "server.ssl.trust-store=classpath:treasury-truststore.p12" >> "$properties_path"
        echo "server.ssl.trust-store-type=PKCS12" >> "$properties_path"
        echo "server.ssl.trust-store-password=changeit" >> "$properties_path"
        echo "server.ssl.client-auth=need" >> "$properties_path"
    fi
    
    # Clean up temporary files
    rm -f "$properties_path.tmp"
    
    write_success "application.properties updated"
}

# Function to create logging configuration
create_logging_config() {
    write_info "Creating logging configuration..."
    
    local logback_path="src/main/resources/logback-spring.xml"
    
    if [[ -f "$logback_path" ]]; then
        write_warning "logback-spring.xml already exists. Skipping creation."
        return 0
    fi
    
    cat > "$logback_path" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property name="LOGS" value="./logs" />

    <appender name="Console"
        class="ch.qos.logback.core.ConsoleAppender">
        <layout class="ch.qos.logback.classic.PatternLayout">
            <Pattern>
                %d{ISO8601} %highlight(%-5level) [%t] %yellow(%C{1.}): %msg%n%throwable
            </Pattern>
        </layout>
    </appender>

    <appender name="RollingFile"
        class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>${LOGS}/spring-boot-logger.log</file>
        <encoder
            class="ch.qos.logback.classic.encoder.PatternLayoutEncoder">
            <Pattern>%d %p %C{1.} [%t] %m%n</Pattern>
        </encoder>

        <rollingPolicy
            class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
            <fileNamePattern>${LOGS}/archived/spring-boot-logger-%d{yyyy-MM-dd}.%i.log
            </fileNamePattern>
            <timeBasedFileNamingAndTriggeringPolicy
                class="ch.qos.logback.core.rolling.SizeAndTimeBasedFNATP">
                <maxFileSize>10MB</maxFileSize>
            </timeBasedFileNamingAndTriggeringPolicy>
        </rollingPolicy>
    </appender>

    <root level="info">
        <appender-ref ref="RollingFile" />
        <appender-ref ref="Console" />
    </root>

    <logger name="com.example.certificate.demo" level="debug" additivity="false">
        <appender-ref ref="RollingFile" />
        <appender-ref ref="Console" />
    </logger>

    <logger name="org.springframework.security" level="debug" additivity="false">
        <appender-ref ref="RollingFile" />
        <appender-ref ref="Console" />
    </logger>

    <logger name="org.springframework.security.web.authentication.preauth.x509" level="debug" additivity="false">
        <appender-ref ref="RollingFile" />
        <appender-ref ref="Console" />
    </logger>

    <logger name="org.apache.tomcat.util.net" level="debug" additivity="false">
        <appender-ref ref="RollingFile" />
        <appender-ref ref="Console" />
    </logger>
</configuration>
EOF
    
    write_success "Logging configuration created"
}

# Function to build the project
build_project() {
    write_info "Building the project..."
    
    export JAVA_HOME="$JAVA_HOME"
    
    if ! ./gradlew clean build; then
        write_error "Gradle build failed"
        exit 1
    fi
    
    write_success "Project built successfully"
}

# Function to start the server
start_server() {
    write_info "Starting the server..."
    
    export JAVA_HOME="$JAVA_HOME"
    
    if [[ "$BUILD_ONLY" == "true" ]]; then
        write_info "Build only mode selected. Server not started."
        return 0
    fi
    
    write_info "Server will start at: https://localhost:8443/api"
    write_info "Press Ctrl+C to stop the server"
    echo ""
    
    # Start server in foreground
    ./gradlew bootRun
}

# Main execution function
main() {
    echo -e "${BLUE}🚀 Treasury Certificate Authentication Demo Setup${NC}"
    echo -e "${GRAY}=================================================${NC}"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Step 1: Find Java installation
    write_step "1" "Detecting Java installation"
    find_java_installation
    
    # Step 2: Install mkcert
    write_step "2" "Installing mkcert"
    install_mkcert_tool
    
    # Step 3: Setup local CA
    write_step "3" "Setting up local Certificate Authority"
    setup_local_ca
    
    # Step 4: Install CA into Java trust store
    write_step "4" "Installing CA into Java trust store"
    install_ca_into_java
    
    # Step 5: Create server keystore
    write_step "5" "Creating server keystore"
    create_server_keystore
    
    # Step 6: Create Treasury trust store
    write_step "6" "Creating Treasury trust store"
    create_treasury_trust_store
    
    # Step 7: Update application.properties
    write_step "7" "Updating application configuration"
    update_application_properties
    
    # Step 8: Create logging configuration
    write_step "8" "Creating logging configuration"
    create_logging_config
    
    # Step 9: Build project
    write_step "9" "Building the project"
    build_project
    
    # Step 10: Start server
    write_step "10" "Starting the server"
    start_server
    
    echo ""
    write_success "Setup completed successfully!"
    write_info "Server URL: https://localhost:8443/api"
    write_info "Logs: ./logs/spring-boot-logger.log"
}

# Run main function with all arguments
main "$@"
