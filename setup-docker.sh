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
if [[ -n "${SETUP_CONF_SCRIPT_FOLDER}" ]]; then
    echo "✅ setup scripts from ${SETUP_CONF_SCRIPT_FOLDER}"
    CONTAINER_ARGS+=("-v" "${SETUP_CONF_SCRIPT_FOLDER}:/etc/mysql/conf.d:ro")
fi

# STARTUP_SCRIPTS
if [[ -n "${SETUP_INIT_SCRIPT_FOLDER}" ]]; then
    echo "✅ startup scripts from ${SETUP_INIT_SCRIPT_FOLDER}"
    CONTAINER_ARGS+=("-v" "${SETUP_INIT_SCRIPT_FOLDER}:/docker-entrypoint-initdb.d")
fi

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
    
    echo "🔎 Container logs:"
    "${CONTAINER_RUNTIME}" logs mariadbcontainer
    
    if [[ "${EXIT_VALUE}" != "1" ]]; then
        echo "::group::✅ Database is ready!"
        # Display password check settings
        echo "🔍 Checking password validation settings..."
        "${CONTAINER_RUNTIME}" exec mariadbcontainer mariadb -u root -e "SELECT @@simple_password_check_digits, @@simple_password_check_letters_same_case, @@simple_password_check_minimal_length, @@simple_password_check_other_characters;"
        # Export database type for subsequent steps
        echo "SETUP_DATABASE_TYPE=container" >> $GITHUB_ENV
        echo "✅ Database type exported: container"
        # Set output variable for the action
        echo "database-type=container" >> $GITHUB_OUTPUT
    else
        echo "::group::❌ Database failed to start or become healthy."
    fi
else
    echo "🔎 Container logs:"
    "${CONTAINER_RUNTIME}" logs mariadbcontainer
    echo "::group::❌ Database failed to start on time."
    EXIT_VALUE=1
fi

echo "::endgroup::"
###############################################################################
exit ${EXIT_VALUE}
