[![License](https://img.shields.io/badge/License-Apache%20License%202.0-brightgreen.svg)][1]
![JavaCI](https://github.com/andifalk/client-certificate-demo/workflows/JavaCI/badge.svg)

# Client Certificate Authentication with Spring Boot

This repository contains a demo on how to implement mutual TLS (_MTLS_) using Spring Boot and Spring Security.
For demonstration purposes the included application implements a simple Spring MVC Rest API:

* The app is connecting using an HTTPS connection (server authenticates to the client)
* It requires a client certificate to authenticate (client authenticates to the server)

The Rest API provides just one endpoint: ```https://localhost:8443/api``` 
that returns the value ```it works for [current_user]``` with _current_user_ being replaced by the
user specified as part of the client certificate.

## System Requirements

For this tutorial you need the following requirements:

* Java JDK version 11 or newer.
* Use a Java IDE of your choice (Just import the repository as a [gradle](https://gradle.org/) project)
* [mkcert](https://mkcert.dev/) to create trusted certificates for localhost. Please follow 
  the [installation instructions](https://github.com/FiloSottile/mkcert#installation) to set this up
  on your machine.
* [Keystore Explorer](https://keystore-explorer.org/) to manage keystore contents. To install it just 
  go to the [Keystore Downloads](https://keystore-explorer.org/downloads.html) page and get the appropriate
  installer for your operating system  
* [Curl](https://curl.haxx.se/) or [Postman](https://www.postman.com/) to access the 
server api using a command line or UI client. 
  
## Getting started

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
- See SETUP_README.md for more information

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

## Getting Started Without PowerShell

To create a local certificate authority (with your own root certificate)
use the following command. Make sure you also have set the _JAVA_HOME_ environment variable if you also want 
to install the root certificate into the trust store of your JDK. You have to repeat this step for each Java JDK you want
to use. 

```shell script
export JAVA_HOME=...
mkcert -install
```

This should give a similar output to this (please note that in this case _mkcert -install_ has been executed before, 
so the root certificate has already been installed in the system and the web browsers, so it was just installed for Java).

```shell script
Using the local CA at "/home/afa/.local/share/mkcert" ✨
The local CA is already installed in the system trust store! 👍
The local CA is already installed in the Firefox and/or Chrome/Chromium trust store! 👍
The local CA is now installed in Java's trust store! ☕️
```

## Setup HTTPS (SSL/TLS) for the application

At first, you need a valid trusted server certificate.  
To create a keystore containing the certificate with private/public key pair 
open a command line terminal then navigate to the subdirectory _src/main/resources_ of this project 
and use the following command.

```shell script
mkcert -p12-file server-keystore.p12 -pkcs12 localhost mydev.local
```

Now you should have created a new file _server-keystore.p12_ in the subdirectory _src/main/resources_.

To enable SSL/TLS in the spring boot application add the following entries to the application.properties

```properties
server.port=8443
server.ssl.enabled=true
server.ssl.key-store=classpath:server-keystore.p12
server.ssl.key-store-type=PKCS12
server.ssl.key-store-password=changeit
server.ssl.key-password=changeit
```

We need the trust store to enable trust between the server application and the client certificate in the web browser.
The property _client_auth_ specifies how mandatory the client certificate authentication is.
Possible values for this property are:

* __need__: The client certificate is mandatory for authentication
* __want__: The client certificate is requested but not mandatory for authentication
* __none__: The client certificate is not used at all

As final step we have to configure X509 client authentication 
in _com.example.certificate.demo.security.WebSecurityConfiguration.java_:

```java
package com.example.certificate.demo.security;

import org.springframework.boot.actuate.autoconfigure.security.servlet.EndpointRequest;
import org.springframework.boot.actuate.health.HealthEndpoint;
import org.springframework.boot.actuate.info.InfoEndpoint;
import org.springframework.context.annotation.Bean;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configuration.WebSecurityConfigurerAdapter;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.annotation.web.configurers.HeadersConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import org.springframework.security.crypto.password.PasswordEncoder;

@EnableWebSecurity
public class WebSecurityConfiguration extends WebSecurityConfigurerAdapter {

  @Bean
  public PasswordEncoder passwordEncoder() {
    return PasswordEncoderFactories.createDelegatingPasswordEncoder();
  }

  @Bean
  public UserDetailsService userDetailsService() {
    return new DemoUserDetailsService(passwordEncoder());
  }

  @Override
  protected void configure(HttpSecurity http) throws Exception {
    http.authorizeRequests(
            ar -> {
              ar.requestMatchers(
                      EndpointRequest.to(HealthEndpoint.class),
                      EndpointRequest.to(InfoEndpoint.class))
                  .permitAll();
              ar.requestMatchers(EndpointRequest.toAnyEndpoint()).authenticated();
              ar.anyRequest().authenticated();
            })
        .headers(h -> h.httpStrictTransportSecurity(HeadersConfigurer.HstsConfig::disable))
        .csrf(AbstractHttpConfigurer::disable)
        .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .x509(
            x -> {
              x.subjectPrincipalRegex("CN=(.*?),");
              x.userDetailsService(userDetailsService());
            });
  }
}
```

The changes above 

* introduce a reference to the _UserDetailsService_ required for the X509 authentication
* disable the Http strict transport security header (do not disable this on production, for localhost this can be a problem for testing other
local web applications not providing a Https connection)
* configure how to get the principle from the client certificate using a regular expression for the common name (CN)

In the referenced class _com.example.certificate.demo.security.DemoUserDetailsService_ we just map
the user data from the certificate to local user entity (implementing the interface _org.springframework.security.core.userdetails.UserDetails_). 

```java
package com.example.certificate.demo.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;

public class DemoUserDetailsService implements UserDetailsService {
  private static final Logger LOGGER = LoggerFactory.getLogger(DemoUserDetailsService.class);

  private final PasswordEncoder passwordEncoder;

  public DemoUserDetailsService(PasswordEncoder passwordEncoder) {
    this.passwordEncoder = passwordEncoder;
  }

  @Override
  public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {

    LOGGER.debug("Got username {}", username);

    if ("myuser".equals(username)) {
      return User.withUsername("myuser")
          .passwordEncoder(passwordEncoder::encode)
          .password("none")
          .roles("USER")
          .build();
    } else {
      throw new UsernameNotFoundException(String.format("No user found for %s", username));
    }
  }
}
```

With these changes we can now also use the authenticated user in the 
class _com.example.certificate.demo.web.DemoRestController_ to show this in the result:

```java
package com.example.certificate.demo.web;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.User;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import static org.springframework.http.HttpStatus.OK;

@RestController
@RequestMapping("/api")
public class DemoRestController {

  @ResponseStatus(OK)
  @GetMapping
  public String api(@AuthenticationPrincipal User user) {
    return "it works for " + user.getUsername();
  }
}
```

That's it, the server implementation is complete.

To build the server with [gradle](https://gradle.org/) just open a shell and perform the command ```gradlew clean build```.

To start the application use [gradle](https://gradle.org/) with the command ```gradlew bootRun``` or start it using your Java IDE.

### Client Test

#### Web Browser

To authenticate your web browser for our Spring Boot server application make sure you have your PIV plugged into your machine.

If you navigate your browser to ```https://localhost:8443/api``` then you first should see
a popup window requesting a client certificate. Depending on your browser configuration
you might have multiple client certificates installed. Make sure you select the one for _myuser_. 

![BrowserCertPopup](images/browser_cert_popup.png)

If the authentication with the selected client certificate succeeds then you should see the output for the Rest API call (please also note that this is also served over a secure HTTPS connection validated by our local CA root certificate).

![BrowserItWorks](images/browser_it_works.png)


### Server-Side Output

To see that the client certificate authentication is really happening on the server side
you can enable logging for spring security X509 authentication on debug level.

_application.properties_

```properties
logging.level.org.springframework.security.web.authentication.preauth.x509=debug
```

After triggering the Rest API via web browser or command line client request you should see details for the
client certificate in the console log:

```shell script
...w.a.p.x.SubjectDnX509PrincipalExtractor : Subject DN is 'CN=myuser, OU=afa@t470p (Andreas Falk), O=mkcert development certificate'
...w.a.p.x.SubjectDnX509PrincipalExtractor : Extracted Principal name is 'myuser'
...o.s.s.w.a.p.x.X509AuthenticationFilter   : X.509 client authentication certificate:[
[
  Version: V3
  Subject: CN=myuser, OU=afa@t470p (Andreas Falk), O=mkcert development certificate
  Signature Algorithm: SHA256withRSA, OID = 1.2.840.113549.1.1.11

  Key:  Sun RSA public key, 2048 bits
  params: null
  modulus: 23253368369848628032893630278772264357078496203018563672085954387826633745536129136649857313719221974767106491857916975819815825901153301887027528238273184100205324281565555173315546049966762048884772732825147885908561417294518669035595678580994138780080507294901720363402887847773305716536408456309527091057847342087496422569307696913977686291755773504037157614914770645759676471925053015098400150869894291252915050242790869713944867413401612480099547989566114401380699576931969698381639431869952458115090562964827206337756791305720687381987297343244586956216230885030841702533261018552511490919859679491601896236721
  public exponent: 65537
  Validity: [From: Sat Jun 01 02:00:00 CEST 2019,
               To: Mon Jan 28 23:26:38 CET 2030]
  Issuer: CN=mkcert afa@t470p (Andreas Falk), OU=afa@t470p (Andreas Falk), O=mkcert development CA
  SerialNumber: [    122d9934 30d7007f 1e9584f1 10f59fff]
...
```

### Reference Documentation
For further reference, please consider the following sections:

* [mkcert (simple tool for making locally-trusted development certificates)](https://github.com/FiloSottile/mkcert)
* [Spring Boot Security Features](https://docs.spring.io/spring-boot/docs/2.2.4.RELEASE/reference/htmlsingle/#boot-features-security)
* [Spring Security X509 Authentication (Servlet Stack)](https://docs.spring.io/spring-security/site/docs/5.3.0.RELEASE/reference/html5/#servlet-x509)
* [Spring Security X509 Authentication (WebFlux Stack)](https://docs.spring.io/spring-security/site/docs/5.3.0.RELEASE/reference/html5/#reactive-x509)
* [The magic of TLS, X509 and mutual authentication explained (medium.com)](https://medium.com/sitewards/the-magic-of-tls-x509-and-mutual-authentication-explained-b2162dec4401)
* [SSL/TLS and PKI History](https://www.feistyduck.com/ssl-tls-and-pki-history/)
* [RFC 8446: The Transport Layer Security (TLS) Protocol Version 1.3](https://tools.ietf.org/html/rfc8446)
* [RFC 5280: Internet X.509 Public Key Infrastructure Certificate and Certificate Revocation List (CRL) Profile](https://tools.ietf.org/html/rfc5280)

## License

Apache 2.0 licensed

[1]:http://www.apache.org/licenses/LICENSE-2.0.txt
