#!/bin/bash
CONTAINER_RUNTIME=""
CONTAINER_ARGS=()
MARIADB_ARGS=()
CONTAINER_IMAGE=""
REGISTRY_PREFIX=""

###############################################################################
echo "::group::🔍 Verifying inputs"

# CONTAINER_RUNTIME
# If the setup container runtime is set, verify the runtime is available
if [[ -n "${SETUP_CONTAINER_RUNTIME}" ]]; then
    # Container runtime exists
    if type "${SETUP_CONTAINER_RUNTIME}" > /dev/null; then
        CONTAINER_RUNTIME="${SETUP_CONTAINER_RUNTIME}"
        echo "✅ container runtime set to ${CONTAINER_RUNTIME}"
    fi
fi
# If container runtime is empty (either doesn't exist, or wasn't passed on), find default
if [[ -z "${CONTAINER_RUNTIME}" ]]; then
  if type podman > /dev/null; then
      CONTAINER_RUNTIME="podman"
      echo "☑️️ container runtime set to ${CONTAINER_RUNTIME} (default)"
  elif type docker > /dev/null; then
      CONTAINER_RUNTIME="docker"
      echo "☑️️ container runtime set to ${CONTAINER_RUNTIME} (default)"
  else
      echo "❌ container runtime not available."
      exit 1;
  fi
fi

# TAG
if [[ -z "${SETUP_TAG}" ]]; then
    SETUP_TAG="latest"
fi

if [[ -z "${SETUP_REGISTRY}" ]]; then
    SETUP_REGISTRY="docker.io/mariadb"
    REGISTRY_PREFIX="docker.io"
else
  if [[ "${SETUP_REGISTRY}" != "docker.io/mariadb" && "${SETUP_REGISTRY}" != "quay.io/mariadb-foundation/mariadb-devel" && "${SETUP_REGISTRY}" != "docker.mariadb.com/enterprise-server" ]]; then
      echo "❌ wrong repository value ${SETUP_REGISTRY}. permit values are 'docker.io/mariadb', 'quay.io/mariadb-foundation/mariadb-devel' or 'docker.mariadb.com/enterprise-server'."
      exit 1;
  fi
  if [[ "${SETUP_REGISTRY}" == "docker.io/mariadb" ]]; then
      REGISTRY_PREFIX="docker.io"
  else
    if [[ "${SETUP_REGISTRY}" == "quay.io/mariadb-foundation/mariadb-devel" ]]; then
      REGISTRY_PREFIX="quay.io"
    else
      REGISTRY_PREFIX="docker.mariadb.com"
    fi
  fi
fi

CONTAINER_IMAGE="${SETUP_REGISTRY}:${SETUP_TAG}"
echo "✅ container image set to ${CONTAINER_IMAGE}"

# PORT
if [[ -z "${SETUP_PORT}" ]]; then
  SETUP_PORT=3306
fi
echo "✅ port set to ${SETUP_PORT}"

CONTAINER_ARGS+=("-p" "3306:${SETUP_PORT}")
CONTAINER_ARGS+=("--name" "mariadbcontainer")

# PASSWORD
if [[ -n "${SETUP_ROOT_PASSWORD}" ]]; then
  CONTAINER_ARGS+=("-e" "MARIADB_ROOT_PASSWORD=\"${SETUP_ROOT_PASSWORD}\"")
  echo "✅ root password is explicitly set"
else
  if [[ -n "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" && ( "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" == "1" || "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" == "yes" ) ]]; then
    CONTAINER_ARGS+=("-e" "MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1")
  else
    CONTAINER_ARGS+=("-e" "MARIADB_RANDOM_ROOT_PASSWORD=1")
    echo "⚠️ root password will be randomly generated"
  fi
fi

# DATABASE
if [[ -n "${SETUP_DATABASE}" ]]; then
    echo "✅ database name set to ${SETUP_DATABASE}"
    CONTAINER_ARGS+=("-e" "MARIADB_DATABASE=${SETUP_DATABASE}")
fi

# USER
if [[ -n "${SETUP_USER}" ]]; then
    echo "✅ mariadb user is explicitly set"
    CONTAINER_ARGS+=("-e" "MARIADB_USER=\"${SETUP_USER}\"")
fi

# PASSWORD
if [[ -n "${SETUP_PASSWORD}" ]]; then
    echo "✅ mariadb password is explicitly set"
    CONTAINER_ARGS+=("-e" "MARIADB_PASSWORD=\"${SETUP_PASSWORD}\"")
fi

# SETUP_SCRIPTS
if [[ -n "${SETUP_SSL_SCRIPT_FOLDER}" ]]; then
    echo "✅ setup scripts from ${SETUP_SSL_SCRIPT_FOLDER}"
    
    # Check if SSL certificate files exist in the conf script folder
    if [[ -f "${SETUP_SSL_SCRIPT_FOLDER}/ca.crt" && -f "${SETUP_SSL_SCRIPT_FOLDER}/server.crt" && -f "${SETUP_SSL_SCRIPT_FOLDER}/server.key" ]]; then
        echo "✅ SSL certificates found in ${SETUP_SSL_SCRIPT_FOLDER}"
        
        # Verify SSL certificates are readable and not empty
        if [[ -s "${SETUP_SSL_SCRIPT_FOLDER}/ca.crt" && -s "${SETUP_SSL_SCRIPT_FOLDER}/server.crt" && -s "${SETUP_SSL_SCRIPT_FOLDER}/server.key" ]]; then
            echo "✅ SSL certificates are valid and non-empty"
            # Mount certificates to a subdirectory to avoid conflicts with existing config files
            CONTAINER_ARGS+=("-v" "${SETUP_SSL_SCRIPT_FOLDER}:/etc/mysql/ssl")
        else
            echo "⚠️ SSL certificates exist but some may be empty"
            CONTAINER_ARGS+=("-v" "${SETUP_SSL_SCRIPT_FOLDER}:/etc/mysql/ssl")
        fi
    else
        echo "⚠️ SSL certificates not found in ${SETUP_SSL_SCRIPT_FOLDER}"
        echo "   Expected files: ca.crt, server.crt, server.key"
        echo "   Mounting configuration folder anyway, but SSL may not work properly"
        CONTAINER_ARGS+=("-v" "${SETUP_SSL_SCRIPT_FOLDER}:/etc/mysql/ssl")
    fi
fi


# SETUP_SCRIPTS
if [[ -n "${SETUP_CONF_SCRIPT_FOLDER}" ]]; then
    echo "✅ setup scripts from ${SETUP_CONF_SCRIPT_FOLDER}"
    CONTAINER_ARGS+=("-v" "${SETUP_CONF_SCRIPT_FOLDER}:/etc/mysql/conf.d")
fi



# STARTUP_SCRIPTS
if [[ -n "${SETUP_INIT_SCRIPT_FOLDER}" ]]; then
    echo "✅ startup scripts from ${SETUP_INIT_SCRIPT_FOLDER}"
    CONTAINER_ARGS+=("-v" "${SETUP_INIT_SCRIPT_FOLDER}:/docker-entrypoint-initdb.d")
fi

# CHARSET - Always set to utf8mb4
echo "✅ charset set to utf8mb4"
MARIADB_ARGS+=("--character-set-server=utf8mb4")

# ADDITIONAL_CONF
if [[ -n "${SETUP_ADDITIONAL_CONF}" ]]; then
    echo "✅ additional conf: ${SETUP_ADDITIONAL_CONF}"
    # Parse the additional conf string into array elements
    # This handles multiple parameters like "--port 3388 --max_allowed_packet 40M"
    # and also handles newline-separated parameters
    additional_conf_array=()
    
    # Check if the configuration contains newlines
    if [[ "$SETUP_ADDITIONAL_CONF" == *$'\n'* ]]; then
        # Handle newline-separated parameters
        while IFS= read -r line; do
            # Skip empty lines and trim whitespace
            line=$(echo "$line" | xargs)
            if [[ -n "$line" ]]; then
                # Add -- prefix if not already present
                if [[ "$line" != --* ]]; then
                    additional_conf_array+=("--$line")
                else
                    additional_conf_array+=("$line")
                fi
            fi
        done <<< "$SETUP_ADDITIONAL_CONF"
    else
        # Handle space-separated parameters (original behavior)
        # Use safe array assignment instead of eval
        IFS=' ' read -ra temp_array <<< "$SETUP_ADDITIONAL_CONF"
        additional_conf_array=("${temp_array[@]}")
    fi
    
    MARIADB_ARGS+=("${additional_conf_array[@]}")
fi

###############################################################################

if [[ -n "${SETUP_REGISTRY_USER}" && -n "${SETUP_REGISTRY_PASSWORD}" ]]; then
  CONTAINER_LOGIN_ARGS=()
  CONTAINER_LOGIN_ARGS+=("--username" "\"${SETUP_REGISTRY_USER}\"")
  CONTAINER_LOGIN_ARGS+=("--password" "\"${SETUP_REGISTRY_PASSWORD}\"")
  CMD="${CONTAINER_RUNTIME} login ${REGISTRY_PREFIX} ${CONTAINER_LOGIN_ARGS[@]} "
  echo "${CMD}"
  eval "${CMD}"
  exit_code=$?
  if [[ "${exit_code}" == "0" ]]; then
      echo "✅ connected to ${REGISTRY_PREFIX}"
  else
      echo "⚠️ fail to connected to ${REGISTRY_PREFIX}"
  fi
else
  if [[ "${SETUP_REGISTRY}" == "docker.mariadb.com/enterprise-server" ]]; then
      echo "❌ registry user and/or password was not set"
      exit 1;
  fi
fi

echo "::endgroup::"



###############################################################################
echo "::group::🐳 Running Container"


CMD="${CONTAINER_RUNTIME} run -d ${CONTAINER_ARGS[@]} ${CONTAINER_IMAGE} ${MARIADB_ARGS[@]}"
echo "${CMD}"
# Run Docker container
eval "${CMD}"
exit_code=$?

echo "::endgroup::"

###############################################################################

if [[ "${exit_code}" == "0" ]]; then
    echo "⏳ Waiting for database to be ready..."
    
    # Initial wait before starting health checks
    sleep 2
    
    # Validate SSL certificates inside container before checking database connection
    echo "🔍 Validating SSL certificates inside container..."
    if "${CONTAINER_RUNTIME}" exec mariadbcontainer bash -c "
        echo '=== SSL CERTIFICATE VALIDATION ==='
        
        # Check SSL directories
        ssl_dir=''
        if [[ -d /etc/mysql/ssl ]]; then
            ssl_dir='/etc/mysql/ssl'
            echo 'SSL directory found: /etc/mysql/ssl/'
        elif [[ -d /etc/mysql/conf.d/ssl ]]; then
            ssl_dir='/etc/mysql/conf.d/ssl'
            echo 'SSL directory found: /etc/mysql/conf.d/ssl/'
        else
            echo '❌ No SSL directory found'
            exit 1
        fi
        
        echo 'SSL directory contents:'
        ls -la \"\$ssl_dir/\"
        echo ''
        
        # Check required SSL files
        ca_file=\"\$ssl_dir/ca.crt\"
        cert_file=\"\$ssl_dir/server.crt\"
        key_file=\"\$ssl_dir/server.key\"
        
        if [[ ! -f \"\$ca_file\" ]]; then
            echo \"❌ CA certificate not found: \$ca_file\"
            exit 1
        fi
        
        if [[ ! -f \"\$cert_file\" ]]; then
            echo \"❌ Server certificate not found: \$cert_file\"
            exit 1
        fi
        
        if [[ ! -f \"\$key_file\" ]]; then
            echo \"❌ Server key not found: \$key_file\"
            exit 1
        fi
        
        echo '✅ All required SSL files found'
        echo ''
        
        # Validate CA certificate
        echo '--- CA Certificate Validation ---'
        if openssl x509 -in \"\$ca_file\" -noout -checkend 0 2>/dev/null; then
            echo '✅ CA certificate is valid'
            openssl x509 -in \"\$ca_file\" -noout -subject -issuer
        else
            echo '❌ CA certificate is invalid or expired'
            openssl x509 -in \"\$ca_file\" -noout -checkend 0 2>&1 || true
            exit 1
        fi
        echo ''
        
        # Validate server certificate
        echo '--- Server Certificate Validation ---'
        if openssl x509 -in \"\$cert_file\" -noout -checkend 0 2>/dev/null; then
            echo '✅ Server certificate is valid'
            openssl x509 -in \"\$cert_file\" -noout -subject -issuer
        else
            echo '❌ Server certificate is invalid or expired'
            openssl x509 -in \"\$cert_file\" -noout -checkend 0 2>&1 || true
            exit 1
        fi
        echo ''
        
        # Validate server key
        echo '--- Server Key Validation ---'
        if openssl rsa -in \"\$key_file\" -check -noout 2>/dev/null; then
            echo '✅ Server key is valid'
        else
            echo '❌ Server key is invalid'
            openssl rsa -in \"\$key_file\" -check -noout 2>&1 || true
            exit 1
        fi
        echo ''
        
        # Verify certificate and key match
        echo '--- Certificate-Key Match Validation ---'
        cert_modulus=\$(openssl x509 -noout -modulus -in \"\$cert_file\" 2>/dev/null)
        key_modulus=\$(openssl rsa -noout -modulus -in \"\$key_file\" 2>/dev/null)
        
        if [[ \"\$cert_modulus\" == \"\$key_modulus\" ]]; then
            echo '✅ Server certificate and key match'
        else
            echo '❌ Server certificate and key do not match'
            exit 1
        fi
        echo ''
        
        echo '🎉 SSL certificate validation completed successfully!'
    "; then
        echo "✅ SSL certificates validated successfully"
    else
        echo "❌ SSL certificate validation failed"
        echo "🔎 Container debug info:"
        "${CONTAINER_RUNTIME}" exec mariadbcontainer bash -c "echo 'SSL-related files:'; find /etc/mysql/ -name '*.crt' -o -name '*.key' -o -name '*.pem' | head -10"
    fi
    
    # Log all MariaDB configuration files
    echo "🔍 Logging MariaDB configuration files..."
    if "${CONTAINER_RUNTIME}" exec mariadbcontainer bash -c "
        echo '=== MARIA DB CONFIGURATION FILES LOG ==='
        
        # Get MariaDB to show all loaded configuration files
        echo '--- MariaDB --verbose --help output ---'
        mariadbd --verbose --help 2>&1 | grep -A 50 'Default options' || echo 'Could not get default options from help'
        echo ''
        
        echo '--- All configuration files in /etc/mysql/ ---'
        echo 'Checking /etc/mysql/ directory structure:'
        ls -la /etc/mysql/ 2>/dev/null || echo 'Directory /etc/mysql/ not found'
        echo ''
        
        echo '=== /etc/my.cnf (MariaDB reads this by default) ==='
        if [[ -f /etc/my.cnf ]]; then
            cat /etc/my.cnf
            echo ''
            echo '--- Processing !includedir directives from /etc/my.cnf ---'
            # Extract includedir paths from my.cnf - handle various formats
            included_dirs=$(grep -E '^\s*!includedir' /etc/my.cnf 2>/dev/null | awk '{print $2}' || true)
            if [[ -n \"\$included_dirs\" ]]; then
                echo \"Found includedir paths: \$included_dirs\"
                echo ''
                for dir in \$included_dirs; do
                    echo \"=== Contents of \$dir ===\"
                    if [[ -d \"\$dir\" ]]; then
                        ls -la \"\$dir\"
                        echo ''
                        echo 'Configuration files in this directory:'
                        find \"\$dir\" -name '*.cnf' -o -name '*.conf' | sort | while read conf_file; do
                            echo \"--- \$conf_file ---\"
                            if [[ -f \"\$conf_file\" ]]; then
                                cat \"\$conf_file\"
                            else
                                echo 'File does not exist'
                            fi
                            echo ''
                        done
                    else
                        echo \"Directory \$dir does not exist\"
                    fi
                    echo ''
                done
            else
                echo 'No !includedir directives found in /etc/my.cnf'
                echo 'Trying alternative detection...'
                # Try to find any line with !includedir
                all_includedir_lines=$(grep -n '!includedir' /etc/my.cnf 2>/dev/null || true)
                if [[ -n \"\$all_includedir_lines\" ]]; then
                    echo \"Found !includedir lines: \$all_includedir_lines\"
                    # Extract paths using sed
                    included_dirs=$(grep '!includedir' /etc/my.cnf 2>/dev/null | sed 's/.*!includedir[[:space:]]*//' | sed 's/[[:space:]]*$//' || true)
                    echo \"Extracted paths: \$included_dirs\"
                    if [[ -n \"\$included_dirs\" ]]; then
                        for dir in \$included_dirs; do
                            echo \"=== Contents of \$dir ===\"
                            if [[ -d \"\$dir\" ]]; then
                                ls -la \"\$dir\"
                                echo ''
                                echo 'Configuration files in this directory:'
                                find \"\$dir\" -name '*.cnf' -o -name '*.conf' | sort | while read conf_file; do
                                    echo \"--- \$conf_file ---\"
                                    if [[ -f \"\$conf_file\" ]]; then
                                        cat \"\$conf_file\"
                                    else
                                        echo 'File does not exist'
                                    fi
                                    echo ''
                                done
                            else
                                echo \"Directory \$dir does not exist\"
                            fi
                            echo ''
                        done
                    fi
                else
                    echo 'No !includedir lines found at all'
                fi
            fi
        else
            echo 'File /etc/my.cnf does not exist'
        fi
        echo ''
        
        echo '=== ~/.my.cnf (MariaDB reads this by default) ==='
        if [[ -f ~/.my.cnf ]]; then
            cat ~/.my.cnf
        else
            echo 'File ~/.my.cnf does not exist'
        fi
        echo ''
        
        echo 'Checking /etc/mysql/conf.d/ directory (NOT read by default):'
        if [[ -d /etc/mysql/conf.d ]]; then
            echo 'conf.d directory exists with contents:'
            ls -la /etc/mysql/conf.d/
            echo ''
            echo 'Configuration files in conf.d (will NOT be loaded by default):'
            find /etc/mysql/conf.d/ -name '*.cnf' -o -name '*.conf' | sort | while read conf_file; do
                echo \"=== \$conf_file ===\"
                if [[ -f \"\$conf_file\" ]]; then
                    cat \"\$conf_file\"
                else
                    echo 'File does not exist'
                fi
                echo ''
            done
        else
            echo 'conf.d directory does not exist'
        fi
        echo ''
        
        echo 'Other configuration files (excluding SSL):'
        find /etc/mysql/ -name '*.cnf' -o -name '*.conf' | grep -v ssl | grep -v conf.d | sort | while read conf_file; do
            echo \"=== \$conf_file ===\"
            if [[ -f \"\$conf_file\" ]]; then
                cat \"\$conf_file\"
            else
                echo 'File does not exist'
            fi
            echo ''
        done
        
        echo '--- MariaDB configuration include test ---'
        echo 'Testing which config files MariaDB would load:'
        if command -v mariadbd &> /dev/null; then
            mariadbd --help --verbose 2>&1 | grep -E '(my.cnf|conf.d)' || echo 'Could not determine config file loading'
        else
            mysqld --help --verbose 2>&1 | grep -E '(my.cnf|conf.d)' || echo 'Could not determine config file loading'
        fi
    "; then
        echo "✅ Configuration files logged successfully"
    else
        echo "⚠️ Could not log all configuration files"
    fi
    
    # Wait for database to be ready by testing connection directly
    timeout=60
    elapsed=0
    connection_ready=false
    
    while [[ $elapsed -lt $timeout ]]; do

        # MariaDB is ready, now test basic connection
        echo "🔍 Testing database connection..."
        # Test connection based on authentication setup
        if [[ -n "${SETUP_ROOT_PASSWORD}" ]]; then
            # Test connection with root password using simple SELECT query
            echo "🔍 Testing connection with: mariadb -h localhost -P ${SETUP_PORT} -u root -p*** -e 'SELECT 1;'"
            if "${CONTAINER_RUNTIME}" exec mariadbcontainer mariadb -h localhost -P "${SETUP_PORT}" -u root -p"${SETUP_ROOT_PASSWORD}" -e "SELECT 1;"; then
                connection_ready=true
            else
                echo "⚠️ Connection test failed, but MariaDB appears ready. Trying again..."
            fi
        elif [[ -n "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" && ( "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" == "1" || "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" == "yes" ) ]]; then
            # Test connection with root and no password
            echo "🔍 Testing connection with: mariadb -h localhost -P ${SETUP_PORT} -u root -e 'SELECT 1;'"
            if "${CONTAINER_RUNTIME}" exec mariadbcontainer mariadb -h localhost -P "${SETUP_PORT}" -u root -e "SELECT 1;"; then
                connection_ready=true
            else
                echo "⚠️ Connection test failed, but MariaDB appears ready. Trying again..."
            fi
        elif [[ -n "${SETUP_USER}" && -n "${SETUP_PASSWORD}" ]]; then
            # Test connection with setup user and password
            echo "🔍 Testing connection with: mariadb -h localhost -P ${SETUP_PORT} -u ${SETUP_USER} -p*** -e 'SELECT 1;'"
            if "${CONTAINER_RUNTIME}" exec mariadbcontainer mariadb -h localhost -P "${SETUP_PORT}" -u "${SETUP_USER}" -p"${SETUP_PASSWORD}" -e "SELECT 1;"; then
                connection_ready=true
            else
                echo "⚠️ Connection test failed, but MariaDB appears ready. Trying again..."
            fi
        else
            # For random password case, just rely on log checking since we can't know the password
            connection_ready=true
        fi

        if [[ "$connection_ready" == "true" ]]; then
            echo "✅ Database connection test passed!"
            break
        fi

        
        sleep 2
        elapsed=$((elapsed + 2))
        echo "⏳ Waiting... (${elapsed}s/${timeout}s) - Container: ${container_status}"
    done
    
    if [[ $elapsed -ge $timeout && "$connection_ready" != "true" ]]; then
        echo "⏰ Timeout reached waiting for database"
        EXIT_VALUE=1
    fi
    
    if [[ "${EXIT_VALUE}" == "1" ]]; then
        echo "::group::❌ Database failed to start or become healthy."
        echo "🔎 Container logs:"
        "${CONTAINER_RUNTIME}" logs mariadbcontainer
        echo "::endgroup::"
    else
        echo "🔎 Container logs:"
        "${CONTAINER_RUNTIME}" logs mariadbcontainer
        echo "::group::✅ Database is ready!"
        # Display password check settings
        echo "🔍 Checking password validation settings..."
        if [[ -n "${SETUP_ROOT_PASSWORD}" ]]; then
            "${CONTAINER_RUNTIME}" exec mariadbcontainer mariadb -u root -p"${SETUP_ROOT_PASSWORD}" -e "SELECT @@simple_password_check_digits, @@simple_password_check_letters_same_case, @@simple_password_check_minimal_length, @@simple_password_check_other_characters;"
        elif [[ -n "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" && ( "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" == "1" || "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" == "yes" ) ]]; then
            "${CONTAINER_RUNTIME}" exec mariadbcontainer mariadb -u root -e "SELECT @@simple_password_check_digits, @@simple_password_check_letters_same_case, @@simple_password_check_minimal_length, @@simple_password_check_other_characters;"
        else
            echo "⚠️ Cannot check password settings: root password is randomly generated"
        fi
        # Export database type for subsequent steps
        echo "SETUP_DATABASE_TYPE=container" >> $GITHUB_ENV
        echo "✅ Database type exported: container"
        # Set output variable for the action
        echo "database-type=container" >> $GITHUB_OUTPUT
        echo "::endgroup::"
    fi
else
    echo "::group::❌ Database failed to start on time."
    echo "🔎 Container logs:"
    "${CONTAINER_RUNTIME}" logs mariadbcontainer
    echo "::endgroup::"
    EXIT_VALUE=1
fi

echo "::endgroup::"
###############################################################################
exit ${EXIT_VALUE}
