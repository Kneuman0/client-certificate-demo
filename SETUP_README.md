# Treasury Certificate Authentication Demo - Automated Setup

This document provides instructions for automating the complete setup of the Treasury Certificate Authentication demo using the provided PowerShell setup script.

## 🚀 Quick Start

### Windows (PowerShell)
```powershell
# Run the complete setup
.\setup-treasury-cert-auth.ps1

# Or with specific Java installation
.\setup-treasury-cert-auth.ps1 -JavaHome "C:\Program Files\Eclipse Adoptium\jdk-17.0.17.10-hotspot"

# Build only (don't start server)
.\setup-treasury-cert-auth.ps1 -BuildOnly

# Skip mkcert installation if already installed
.\setup-treasury-cert-auth.ps1 -SkipMkcert
```

## 📋 Prerequisites

### Required Software
- **Windows 10/11** with PowerShell 5.1+
- **Java 17+** (JDK with keytool)
- **Gradle 7.0+** (included with project)
- **Git** (for cloning repository)
- **Winget** (included with Windows 10/11)

### Administrator Privileges
- Required for installing certificates into Java trust store
- Run PowerShell as Administrator

## 🔧 What the Script Does

### Step-by-Step Automation

1. **🔍 Java Detection**
   - Auto-detects Java installation
   - Supports multiple Java distributions
   - Validates keytool availability

2. **📦 mkcert Installation**
   - Installs mkcert certificate tool via winget
   - Configures local development CA
   - Handles existing installations

3. **🔐 Certificate Authority Setup**
   - Creates local development CA
   - Installs CA into system trust store
   - Installs CA into Java trust store

4. **🗄️ Server Keystore Creation**
   - Generates server certificate for localhost
   - Creates PKCS12 keystore with private key
   - Configures certificate chain

5. **🏛️ Treasury Trust Store Setup**
   - Imports Treasury Root CA certificate
   - Imports Treasury OCIO CA certificate
   - Adds mkcert CA for testing compatibility

6. **⚙️ Application Configuration**
   - Updates application.properties
   - Configures SSL/TLS settings
   - Enables client certificate authentication

7. **📝 Logging Configuration**
   - Creates detailed logging setup
   - Configures X509 authentication logging
   - Sets up file-based logging

8. **🏗️ Project Build**
   - Cleans and builds the project
   - Validates configuration
   - Prepares for deployment

9. **🚀 Server Startup**
   - Starts the Spring Boot application
   - Configures HTTPS on port 8443
   - Enables mutual TLS authentication

## 📁 Generated Files

### Certificate Files
```
src/main/resources/
├── server-keystore.p12          # Server certificate + private key
├── treasury-truststore.p12      # Treasury CA certificates
├── Treasury-Root-CA.cer         # Treasury Root CA certificate
├── Treasury-OCIO-CA.cer         # Treasury OCIO CA certificate
└── logback-spring.xml           # Logging configuration
```

### Configuration Files
```
src/main/resources/
└── application.properties       # Updated SSL configuration
```

### Log Files
```
logs/
├── spring-boot-logger.log       # Application logs
└── archived/                    # Rotated log files
```

## 🛠️ Script Parameters

### PowerShell Script Parameters
```powershell
[Parameter] Description
----------- -----------
-JavaHome    Path to Java installation (auto-detected if not specified)
-SkipMkcert  Skip mkcert installation if already installed
-BuildOnly   Only build the project, don't start the server
```

## 🔍 Troubleshooting

### Common Issues

#### Java Not Found
```
Error: Java installation not found
Solution: Set JAVA_HOME environment variable or use -JavaHome parameter
```

#### Permission Denied (Java Trust Store)
```
Error: Access is denied when installing CA certificate
Solution: Run PowerShell as Administrator
```

#### mkcert Installation Failed
```
Error: mkcert installation failed
Solution: Install mkcert manually from https://github.com/FiloSottile/mkcert
```

#### Build Failed
```
Error: Gradle build failed
Solution: Check Java version and network connectivity
```

### Manual Steps

If the automated script fails, you can perform these steps manually:

1. **Install mkcert manually**
   ```powershell
   winget install FiloSottile.mkcert
   ```

2. **Setup local CA**
   ```powershell
   mkcert -install
   ```

3. **Install CA into Java**
   ```powershell
   keytool -importcert -storepass changeit -noprompt -trustcacerts `
           -alias mkcert-local-ca -cacerts -file "$env:LOCALAPPDATA\mkcert\rootCA.pem"
   ```

4. **Create server keystore**
   ```powershell
   mkcert -p12-file server-keystore.p12 -pkcs12 localhost mydev.local
   ```

## 🌐 Accessing the Application

After successful setup:

1. **Server URL**: `https://localhost:8443/api`
2. **Health Check**: `https://localhost:8443/actuator/health`
3. **Logs**: `./logs/spring-boot-logger.log`

### Browser Testing
1. Import your Treasury client certificate into your browser
2. Navigate to `https://localhost:8443/api`
3. Select your Treasury certificate when prompted
4. Expected response: `"it works for Kyle P. Neuman"`

### Command Line Testing
```powershell
# With client certificate
curl --cert your-client.p12:changeit --cert-type p12 https://localhost:8443/api

# With separate cert and key
curl --cert your-cert.cer --key your-key.pem https://localhost:8443/api
```

## 🔒 Security Considerations

### Development Environment
- Uses mkcert for development certificates
- Passwords are set to "changeit" (default)
- Debug logging is enabled

### Production Deployment
- Replace with production certificates
- Use strong, unique passwords
- Disable debug logging
- Configure proper certificate rotation

## 📞 Support

If you encounter issues:

1. Check the log files in `./logs/spring-boot-logger.log`
2. Verify all prerequisites are installed
3. Ensure proper permissions for certificate operations
4. Test with manual steps if automation fails

## 🔄 Maintenance

### Certificate Renewal
- Server certificates: Regenerate with mkcert
- Treasury certificates: Update from Treasury PKI
- Trust store: Re-import updated certificates

### Configuration Updates
- Modify `application.properties` for production settings
- Update `logback-spring.xml` for production logging
- Adjust security configurations as needed
