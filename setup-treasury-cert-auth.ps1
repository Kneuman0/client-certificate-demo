#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Automated setup script for Treasury Certificate Authentication Demo
.DESCRIPTION
    This script automates the complete setup of the Spring Boot client certificate
    authentication demo with Treasury certificates, including:
    - Install mkcert and create local CA
    - Install CA into Java trust store
    - Create server keystore
    - Configure Treasury trust store
    - Update application configuration
    - Build and start the server
.PARAMETER JavaHome
        Path to Java installation (auto-detected if not specified)
.PARAMETER SkipMkcert
        Skip mkcert installation if already installed
.PARAMETER BuildOnly
        Only build the project, don't start the server
.EXAMPLE
    .\setup-treasury-cert-auth.ps1
.EXAMPLE
    .\setup-treasury-cert-auth.ps1 -JavaHome "C:\Program Files\Eclipse Adoptium\jdk-17.0.17.10-hotspot"
#>

[CmdletBinding()]
param(
    [string]$JavaHome = "",
    [switch]$SkipMkcert = $false,
    [switch]$BuildOnly = $false
)

# Enhanced error handling
$ErrorActionPreference = "Stop"

# Color output functions
function Write-Success($message) {
    Write-Host "SUCCESS: $message" -ForegroundColor Green
}

function Write-Info($message) {
    Write-Host "INFO: $message" -ForegroundColor Cyan
}

function Write-Warning($message) {
    Write-Host "WARNING: $message" -ForegroundColor Yellow
}

function Write-Error($message) {
    Write-Host "ERROR: $message" -ForegroundColor Red
}

function Write-Step($step, $message) {
    Write-Host ""
    Write-Host "Step ${step}: $message" -ForegroundColor Magenta
    Write-Host "------------------------------------------------" -ForegroundColor Gray
}

# Check if running as Administrator for certain operations
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to find Java installation
function Find-JavaInstallation {
    Write-Info "Detecting Java installation..."
    
    # Try to find Java in common locations
    $javaPaths = @(
        "C:\Program Files\Eclipse Adoptium\jdk-17.0.17.10-hotspot",
        "C:\Program Files\Eclipse Adoptium\jdk-*",
        "C:\Program Files\Java\jdk-17",
        "C:\Program Files\Java\jdk-*"
    )
    
    foreach ($path in $javaPaths) {
        $found = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Where-Object { 
            Test-Path "$($_.FullName)\bin\keytool.exe" 
        } | Select-Object -First 1
        
        if ($found) {
            return $found.FullName
        }
    }
    
    # Try using java command to find installation
    try {
        $javaCmd = Get-Command java -ErrorAction SilentlyContinue
        if ($javaCmd) {
            $javaHome = Split-Path (Split-Path $javaCmd.Source -Parent) -Parent
            if (Test-Path "$javaHome\bin\keytool.exe") {
                return $javaHome
            }
        }
    } catch {
        # Continue to next method
    }
    
    throw "Java installation not found. Please specify -JavaHome parameter"
}

# Function to install mkcert
function Install-MkcertTool {
    Write-Info "Installing mkcert..."
    
    try {
        # Check if mkcert is already installed
        $mkcertCmd = Get-Command mkcert -ErrorAction SilentlyContinue
        if ($mkcertCmd) {
            if (-not $SkipMkcert) {
                Write-Warning "mkcert is already installed. Use -SkipMkcert to skip reinstallation."
            }
            return $mkcertCmd.Source
        }
        
        if (-not $SkipMkcert) {
            Write-Info "Installing mkcert via winget..."
            winget install FiloSottile.mkcert --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            
            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            
            # Find mkcert installation
            $mkcertPath = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FiloSottile.mkcert*" -Recurse -Filter "mkcert.exe" | Select-Object -First 1 -ExpandProperty FullName
            
            if (-not $mkcertPath) {
                throw "mkcert installation failed"
            }
            
            Write-Success "mkcert installed at: $mkcertPath"
            return $mkcertPath
        }
        
        # If SkipMkcert is true, try to find existing installation
        $mkcertPath = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FiloSottile.mkcert*" -Recurse -Filter "mkcert.exe" | Select-Object -First 1 -ExpandProperty FullName
        if ($mkcertPath) {
            Write-Info "Found existing mkcert at: $mkcertPath"
            return $mkcertPath
        }
        
        throw "mkcert not found. Cannot skip installation."
    } catch {
        throw "Failed to install mkcert: $($_.Exception.Message)"
    }
}

# Function to setup local CA
function Set-LocalCA {
    param([string]$MkcertPath, [string]$JavaHome)
    
    Write-Info "Setting up local Certificate Authority..."
    Write-Info "Using mkcert path: $MkcertPath"
    
    try {
        # Check if mkcert file exists
        if (-not (Test-Path $MkcertPath)) {
            throw "mkcert executable not found at: $MkcertPath"
        }
        
        # Set JAVA_HOME for mkcert
        $env:JAVA_HOME = $JavaHome
        
        # Install local CA using call operator to avoid execution issues
        & $MkcertPath -install
        
        if ($LASTEXITCODE -ne 0) {
            throw "mkcert -install failed with exit code $LASTEXITCODE"
        }
        
        Write-Success "Local CA installed successfully"
    } catch {
        throw "Failed to setup local CA: $($_.Exception.Message)"
    }
}

# Function to install CA into Java trust store
function Install-CAIntoJava {
    param([string]$JavaHome)
    
    Write-Info "Installing CA into Java trust store..."
    
    try {
        $keytoolPath = "$JavaHome\bin\keytool.exe"
        $caCertPath = "$env:LOCALAPPDATA\mkcert\rootCA.pem"
        
        if (-not (Test-Path $caCertPath)) {
            throw "mkcert CA certificate not found at $caCertPath"
        }
        
        # Check if already installed
        & $keytoolPath -list -cacerts -alias "mkcert-local-ca" -storepass changeit 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Warning "mkcert CA is already installed in Java trust store"
            return
        }
        
        # Install CA certificate
        & $keytoolPath -importcert -storepass changeit -noprompt -trustcacerts -alias "mkcert-local-ca" -cacerts -file $caCertPath
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to import CA certificate into Java trust store"
        }
        
        Write-Success "CA certificate installed into Java trust store"
    } catch {
        if ($_.Exception.Message -like "*Access is denied*") {
            Write-Warning "Administrator privileges required to modify Java trust store"
            Write-Info "Please run this script as Administrator or manually run:"
            Write-Info "& `"$JavaHome\bin\keytool.exe`" -importcert -storepass changeit -noprompt -trustcacerts -alias `"mkcert-local-ca`" -cacerts -file `"$caCertPath`""
        } else {
            throw "Failed to install CA into Java trust store: $($_.Exception.Message)"
        }
    }
}

# Function to create server keystore
function New-ServerKeystore {
    param([string]$MkcertPath)
    
    Write-Info "Creating server keystore..."
    
    try {
        $keystorePath = "src\main\resources\server-keystore.p12"
        
        if (Test-Path $keystorePath) {
            Write-Warning "Server keystore already exists. Skipping creation."
            return
        }
        
        # Create server keystore
        & $MkcertPath -p12-file server-keystore.p12 -pkcs12 localhost mydev.local
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create server keystore"
        }
        
        # Move to resources directory if created in current directory
        if (Test-Path "server-keystore.p12") {
            Move-Item "server-keystore.p12" $keystorePath -Force
        }
        
        Write-Success "Server keystore created at: $keystorePath"
    } catch {
        throw "Failed to create server keystore: $($_.Exception.Message)"
    }
}

# Function to create Treasury trust store
function New-TreasuryTrustStore {
    param([string]$JavaHome)
    
    Write-Info "Creating Treasury trust store..."
    
    try {
        $keytoolPath = "$JavaHome\bin\keytool.exe"
        $trustStorePath = "src\main\resources\treasury-truststore.p12"
        $rootCertPath = "src\main\resources\Treasury-Root-CA.cer"
        $ocioCertPath = "src\main\resources\Treasury-OCIO-CA.cer"
        $mkcertCaPath = "$env:LOCALAPPDATA\mkcert\rootCA.pem"
        
        # Check if Treasury certificates exist
        if (-not (Test-Path $rootCertPath)) {
            throw "Treasury Root CA certificate not found at $rootCertPath"
        }
        if (-not (Test-Path $ocioCertPath)) {
            throw "Treasury OCIO CA certificate not found at $ocioCertPath"
        }
        
        # Remove existing trust store if it exists
        if (Test-Path $trustStorePath) {
            Remove-Item $trustStorePath -Force
            Write-Info "Removed existing Treasury trust store"
        }
        
        # Import Treasury Root CA
        & $keytoolPath -importcert -storepass changeit -noprompt -trustcacerts -alias "treasury-root-ca" -keystore $trustStorePath -storetype PKCS12 -file $rootCertPath
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to import Treasury Root CA"
        }
        
        # Import Treasury OCIO CA
        & $keytoolPath -importcert -storepass changeit -noprompt -trustcacerts -alias "treasury-ocio-ca" -keystore $trustStorePath -storetype PKCS12 -file $ocioCertPath
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to import Treasury OCIO CA"
        }
        
        # Import mkcert CA for testing
        if (Test-Path $mkcertCaPath) {
            & $keytoolPath -importcert -storepass changeit -noprompt -trustcacerts -alias "mkcert-ca" -keystore $trustStorePath -storetype PKCS12 -file $mkcertCaPath
            
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to import mkcert CA (non-critical)"
            }
        }
        
        Write-Success "Treasury trust store created at: $trustStorePath"
    } catch {
        throw "Failed to create Treasury trust store: $($_.Exception.Message)"
    }
}

# Function to update application.properties
function Update-ApplicationProperties {
    Write-Info "Updating application.properties..."
    
    try {
        $propertiesPath = "src\main\resources\application.properties"
        
        if (-not (Test-Path $propertiesPath)) {
            throw "application.properties not found"
        }
        
        $properties = Get-Content $propertiesPath
        
        # Update or add properties
        $updatedProperties = @()
        $trustStoreConfigured = $false
        
        foreach ($line in $properties) {
            if ($line.StartsWith("server.ssl.trust-store=")) {
                $updatedProperties += "server.ssl.trust-store=classpath:treasury-truststore.p12"
                $trustStoreConfigured = $true
            } elseif ($line.StartsWith("server.ssl.trust-store-type=")) {
                $updatedProperties += "server.ssl.trust-store-type=PKCS12"
            } elseif ($line.StartsWith("server.ssl.client-auth=")) {
                $updatedProperties += "server.ssl.client-auth=need"
            } else {
                $updatedProperties += $line
            }
        }
        
        # Add trust store configuration if not present
        if (-not $trustStoreConfigured) {
            $updatedProperties += "server.ssl.trust-store=classpath:treasury-truststore.p12"
            $updatedProperties += "server.ssl.trust-store-type=PKCS12"
            $updatedProperties += "server.ssl.trust-store-password=changeit"
            $updatedProperties += "server.ssl.client-auth=need"
        }
        
        Set-Content -Path $propertiesPath -Value $updatedProperties -Encoding UTF8
        Write-Success "application.properties updated"
    } catch {
        throw "Failed to update application.properties: $($_.Exception.Message)"
    }
}

# Function to create logging configuration
function New-LoggingConfig {
    Write-Info "Creating logging configuration..."
    
    try {
        $logbackPath = "src\main\resources\logback-spring.xml"
        
        if (Test-Path $logbackPath) {
            Write-Warning "logback-spring.xml already exists. Skipping creation."
            return
        }
        
        $logbackConfig = @'
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
'@
        
        Set-Content -Path $logbackPath -Value $logbackConfig -Encoding UTF8
        Write-Success "Logging configuration created"
    } catch {
        throw "Failed to create logging configuration: $($_.Exception.Message)"
    }
}

# Function to build the project
function Invoke-ProjectBuild {
    param([string]$JavaHome)
    
    Write-Info "Building the project..."
    
    $env:JAVA_HOME = $JavaHome
    
    # Clean and build
    .\gradlew clean build
    
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed"
    }
    
    Write-Success "Project built successfully"
}

# Function to start the server
function Start-Server {
    param([string]$JavaHome)
    
    Write-Info "Starting the server..."
    
    try {
        $env:JAVA_HOME = $JavaHome
        
        if ($BuildOnly) {
            Write-Info "Build only mode selected. Server not started."
            return
        }
        
        Write-Info "Server will start at: https://localhost:8443/api"
        Write-Info "Press Ctrl+C to stop the server"
        Write-Host ""
        
        # Start server in foreground
        .\gradlew bootRun
    } catch {
        throw "Failed to start server: $($_.Exception.Message)"
    }
}

# Main execution
function Main {
    try {
        Write-Host "Treasury Certificate Authentication Demo Setup" -ForegroundColor Blue
        Write-Host "=================================================" -ForegroundColor Gray
        
        # Step 1: Find Java installation
        Write-Step "1" "Detecting Java installation"
        if (-not $JavaHome) {
            $JavaHome = Find-JavaInstallation
        }
        Write-Success "Java found at: $JavaHome"
        
        # Step 2: Install mkcert
        Write-Step "2" "Installing mkcert"
        $mkcertPath = Install-MkcertTool
        
        # Step 3: Setup local CA
        Write-Step "3" "Setting up local Certificate Authority"
        Set-LocalCA -MkcertPath $mkcertPath -JavaHome $JavaHome
        
        # Step 4: Install CA into Java trust store
        Write-Step "4" "Installing CA into Java trust store"
        Install-CAIntoJava -JavaHome $JavaHome
        
        # Step 5: Create server keystore
        Write-Step "5" "Creating server keystore"
        New-ServerKeystore -MkcertPath $mkcertPath
        
        # Step 6: Create Treasury trust store
        Write-Step "6" "Creating Treasury trust store"
        New-TreasuryTrustStore -JavaHome $JavaHome
        
        # Step 7: Update application.properties
        Write-Step "7" "Updating application configuration"
        Update-ApplicationProperties
        
        # Step 8: Create logging configuration
        Write-Step "8" "Creating logging configuration"
        New-LoggingConfig
        
        # Step 9: Build project
        Write-Step "9" "Building the project"
        Invoke-ProjectBuild -JavaHome $JavaHome
        
        # Step 10: Start server
        Write-Step "10" "Starting the server"
        Start-Server -JavaHome $JavaHome
        
        Write-Host ""
        Write-Success "Setup completed successfully!"
        Write-Info "Server URL: https://localhost:8443/api"
        Write-Info "Logs: ./logs/spring-boot-logger.log"
        
    } catch {
        Write-Error "Setup failed: $($_.Exception.Message)"
        exit 1
    }
}

# Run main function
Main
