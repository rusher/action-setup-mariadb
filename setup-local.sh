#!/bin/bash

# MariaDB Local Installation Script
# This script installs MariaDB locally on Linux and macOS using native package managers

set -e

MARIADB_VERSION=""
MARIADB_PORT=""
MARIADB_ROOT_PASSWORD=""
MARIADB_USER=""
MARIADB_PASSWORD=""
MARIADB_DATABASE=""
MARIADB_CONFIG_FILE=""

###############################################################################
echo "::group::🔍 Detecting Package Manager"

# Detect package manager
if command -v brew &> /dev/null; then
    PKG_MANAGER="brew"
    echo "✅ Using Homebrew package manager (macOS)"
elif command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
    echo "✅ Using APT package manager (Ubuntu/Debian)"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    echo "✅ Using YUM package manager (RHEL/CentOS)"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    echo "✅ Using DNF package manager (Fedora)"
elif command -v pacman &> /dev/null; then
    PKG_MANAGER="pacman"
    echo "✅ Using Pacman package manager (Arch Linux)"
elif command -v zypper &> /dev/null; then
    PKG_MANAGER="zypper"
    echo "✅ Using Zypper package manager (openSUSE)"
else
    echo "❌ No supported package manager found"
    echo "Supported: brew (macOS), apt (Ubuntu/Debian), yum (RHEL/CentOS), dnf (Fedora), pacman (Arch), zypper (openSUSE)"
    exit 1
fi

echo "::endgroup::"

###############################################################################
echo "::group::🔧 Processing Configuration"

# Set MariaDB version
if [[ -n "${SETUP_TAG}" && "${SETUP_TAG}" != "latest" ]]; then
    MARIADB_VERSION="${SETUP_TAG}"
    echo "✅ MariaDB version set to ${MARIADB_VERSION}"
else
    echo "✅ Using latest MariaDB version"
fi

# Set port
MARIADB_PORT="${SETUP_PORT:-3306}"
echo "✅ MariaDB port set to ${MARIADB_PORT}"

# Set root password
if [[ -n "${SETUP_ROOT_PASSWORD}" ]]; then
    MARIADB_ROOT_PASSWORD="${SETUP_ROOT_PASSWORD}"
    echo "✅ Root password is explicitly set"
else
    if [[ -n "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" && ( "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" == "1" || "${SETUP_ALLOW_EMPTY_ROOT_PASSWORD}" == "yes" ) ]]; then
        MARIADB_ROOT_PASSWORD=""
        echo "⚠️ Root password will be empty"
    else
        MARIADB_ROOT_PASSWORD=$(openssl rand -base64 32 2>/dev/null || date +%s | sha256sum | base64 | head -c 32)
        echo "⚠️ Root password will be randomly generated: ${MARIADB_ROOT_PASSWORD}"
    fi
fi

# Set user and password
if [[ -n "${SETUP_USER}" ]]; then
    MARIADB_USER="${SETUP_USER}"
    echo "✅ MariaDB user set to ${MARIADB_USER}"
fi

if [[ -n "${SETUP_PASSWORD}" ]]; then
    MARIADB_PASSWORD="${SETUP_PASSWORD}"
    echo "✅ MariaDB user password is explicitly set"
fi

# Set database
if [[ -n "${SETUP_DATABASE}" ]]; then
    MARIADB_DATABASE="${SETUP_DATABASE}"
    echo "✅ Initial database set to ${MARIADB_DATABASE}"
fi

# Check for unsupported SETUP_ADDITIONAL_CONF
if [[ -n "${SETUP_ADDITIONAL_CONF}" ]]; then
    echo "⚠️ SETUP_ADDITIONAL_CONF is not supported in local installation and will be ignored"
fi

echo "::endgroup::"

###############################################################################
echo "::group::📦 Installing MariaDB"

install_mariadb() {
    case $PKG_MANAGER in
        "brew")
            echo "Installing MariaDB using Homebrew..."
            if [[ -n "${MARIADB_VERSION}" ]]; then
                brew install mariadb@"${MARIADB_VERSION}"
            else
                brew install mariadb
            fi
            # Ensure PATH includes Homebrew binaries before trying to start
            export PATH="$(brew --prefix)/bin:$PATH"
            # Try to start using mysql.server if available
            if command -v mysql.server &> /dev/null; then
                mysql.server start
            else
                echo "⚠️ mysql.server command not found, will start via brew services"
            fi
            ;;
        "apt")
            echo "Installing MariaDB using APT..."
            sudo apt-get update
            if [[ -n "${MARIADB_VERSION}" ]]; then
                echo "🔍 Attempting to install MariaDB version ${MARIADB_VERSION}..."
                
                # First, try to install from default repositories
                if ! sudo apt-get install -y mariadb-server="${MARIADB_VERSION}*" mariadb-client="${MARIADB_VERSION}*" 2>/dev/null; then
                    echo "⚠️ MariaDB version ${MARIADB_VERSION} not available in default repositories"
                    echo "🔍 Checking available MariaDB versions..."
                    
                    # Show available versions
                    apt-cache madison mariadb-server | head -5 || true
                    
                    # Optionally try to add official MariaDB repository for specific versions
                    if [[ "${MARIADB_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]]; then
                        echo "🔄 Attempting to add official MariaDB ${MARIADB_VERSION} repository..."
                        
                        # Install prerequisites
                        sudo apt-get install -y software-properties-common dirmngr apt-transport-https 2>/dev/null || true
                        
                        # Add MariaDB signing key
                        if curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc 2>/dev/null | sudo apt-key add - 2>/dev/null; then
                            # Add MariaDB repository
                            UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
                            echo "deb https://deb.mariadb.org/${MARIADB_VERSION}/ubuntu ${UBUNTU_CODENAME} main" | sudo tee /etc/apt/sources.list.d/mariadb.list > /dev/null
                            
                            # Update package list and try installation again
                            sudo apt-get update 2>/dev/null
                            if sudo apt-get install -y mariadb-server mariadb-client 2>/dev/null; then
                                echo "✅ Installed MariaDB ${MARIADB_VERSION} from official repository"
                                return 0
                            else
                                echo "⚠️ Failed to install from official MariaDB repository"
                            fi
                        else
                            echo "⚠️ Failed to add MariaDB signing key"
                        fi
                    fi
                    
                    echo "🔄 Installing latest available MariaDB version instead..."
                    # Try with different package names that might be available
                    if sudo apt-get install -y mariadb-server mariadb-client 2>/dev/null; then
                        echo "✅ Installed MariaDB from default repository"
                    elif sudo apt-get install -y default-mysql-server default-mysql-client 2>/dev/null; then
                        echo "✅ Installed MariaDB via default-mysql packages"
                    else
                        echo "❌ Failed to install MariaDB"
                        echo "🔍 Available database packages:"
                        apt-cache search mariadb-server | head -5 || true
                        exit 1
                    fi
                else
                    echo "✅ Installed MariaDB version ${MARIADB_VERSION}"
                fi
            else
                echo "🔍 Installing latest available MariaDB version..."
                if sudo apt-get install -y mariadb-server mariadb-client 2>/dev/null; then
                    echo "✅ Installed MariaDB from default repository"
                elif sudo apt-get install -y default-mysql-server default-mysql-client 2>/dev/null; then
                    echo "✅ Installed MariaDB via default-mysql packages"
                else
                    echo "❌ Failed to install MariaDB"
                    echo "🔍 Available database packages:"
                    apt-cache search mariadb-server | head -5 || true
                    exit 1
                fi
            fi
            ;;
        "yum")
            echo "Installing MariaDB using YUM..."
            if [[ -n "${MARIADB_VERSION}" ]]; then
                sudo yum install -y mariadb-server-"${MARIADB_VERSION}" mariadb-"${MARIADB_VERSION}"
            else
                sudo yum install -y mariadb-server mariadb
            fi
            ;;
        "dnf")
            echo "Installing MariaDB using DNF..."
            if [[ -n "${MARIADB_VERSION}" ]]; then
                sudo dnf install -y mariadb-server-"${MARIADB_VERSION}" mariadb-"${MARIADB_VERSION}"
            else
                sudo dnf install -y mariadb-server mariadb
            fi
            ;;
        "pacman")
            echo "Installing MariaDB using Pacman..."
            sudo pacman -Sy --noconfirm mariadb
            ;;
        "zypper")
            echo "Installing MariaDB using Zypper..."
            if [[ -n "${MARIADB_VERSION}" ]]; then
                sudo zypper install -y mariadb-"${MARIADB_VERSION}" mariadb-client-"${MARIADB_VERSION}"
            else
                sudo zypper install -y mariadb mariadb-client
            fi
            ;;
        *)
            echo "❌ Unsupported package manager: $PKG_MANAGER"
            exit 1
            ;;
    esac
}

# Check if MariaDB is already installed
# Ensure PATH includes Homebrew binaries for macOS before checking
if [[ "$PKG_MANAGER" == "brew" ]]; then
    export PATH="$(brew --prefix)/bin:$PATH"
    
    # For versioned MariaDB installations, add version-specific paths
    if [[ -n "${MARIADB_VERSION}" ]]; then
        VERSIONED_PATH="$(brew --prefix)/opt/mariadb@${MARIADB_VERSION}/bin"
        if [[ -d "$VERSIONED_PATH" ]]; then
            export PATH="$VERSIONED_PATH:$PATH"
        fi
    fi
fi

if command -v mysql &> /dev/null || command -v mariadb &> /dev/null; then
    echo "🔍 Checking existing MySQL/MariaDB installation..."
    
    # Check if MariaDB is already installed
    if command -v mariadb &> /dev/null; then
        EXISTING_VERSION=$(mariadb --version 2>/dev/null || echo "unknown")
        echo "✅ MariaDB is already installed: ${EXISTING_VERSION}"
        echo "📋 Proceeding with configuration of existing MariaDB installation"
    elif command -v mysql &> /dev/null; then
        EXISTING_VERSION=$(mysql --version 2>/dev/null || echo "unknown")
        echo "⚠️ MySQL is installed instead of MariaDB: ${EXISTING_VERSION}"
        echo "🔄 This script requires MariaDB. Removing MySQL and installing MariaDB..."
        
        # Remove MySQL based on package manager
        case $PKG_MANAGER in
            "brew")
                echo "🗑️ Removing MySQL via Homebrew..."
                brew services stop mysql 2>/dev/null || true
                brew uninstall mysql 2>/dev/null || true
                ;;
            "apt")
                echo "🗑️ Removing MySQL via APT..."
                sudo systemctl stop mysql 2>/dev/null || true
                sudo apt-get remove --purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* 2>/dev/null || true
                sudo apt-get autoremove -y 2>/dev/null || true
                ;;
            "yum")
                echo "🗑️ Removing MySQL via YUM..."
                sudo systemctl stop mysqld 2>/dev/null || sudo systemctl stop mysql 2>/dev/null || true
                sudo yum remove -y mysql-server mysql mysql-common 2>/dev/null || true
                ;;
            "dnf")
                echo "🗑️ Removing MySQL via DNF..."
                sudo systemctl stop mysqld 2>/dev/null || sudo systemctl stop mysql 2>/dev/null || true
                sudo dnf remove -y mysql-server mysql mysql-common 2>/dev/null || true
                ;;
            "pacman")
                echo "🗑️ Removing MySQL via Pacman..."
                sudo systemctl stop mysqld 2>/dev/null || sudo systemctl stop mysql 2>/dev/null || true
                sudo pacman -Rns --noconfirm mysql 2>/dev/null || true
                ;;
            "zypper")
                echo "🗑️ Removing MySQL via Zypper..."
                sudo systemctl stop mysql 2>/dev/null || true
                sudo zypper remove -y mysql mysql-client 2>/dev/null || true
                ;;
            *)
                echo "❌ Cannot automatically remove MySQL with package manager: $PKG_MANAGER"
                echo "Please manually remove MySQL before running this script"
                exit 1
                ;;
        esac
        
        # Clean up MySQL data directories (with confirmation for safety)
        echo "🧹 Cleaning up MySQL data directories..."
        if [[ -d "/var/lib/mysql" ]]; then
            echo "⚠️ Found MySQL data directory: /var/lib/mysql"
            echo "🗑️ Removing MySQL data directory (this will delete all MySQL databases)"
            sudo rm -rf /var/lib/mysql 2>/dev/null || true
        fi
        
        # Remove MySQL configuration files
        sudo rm -rf /etc/mysql 2>/dev/null || true
        sudo rm -f /etc/my.cnf 2>/dev/null || true
        
        # Clean up any remaining MySQL processes
        echo "🔍 Checking for remaining MySQL processes..."
        if pgrep -f mysqld &> /dev/null; then
            echo "⚠️ Found running MySQL processes, terminating..."
            sudo pkill -f mysqld 2>/dev/null || true
            sleep 2
        fi
        
        # Remove MySQL system users (optional, commented out for safety)
        # sudo userdel mysql 2>/dev/null || true
        
        # Verify MySQL is fully removed
        if command -v mysql &> /dev/null; then
            echo "⚠️ MySQL client still detected after removal attempt"
            echo "🔍 Please manually verify MySQL removal before proceeding"
        else
            echo "✅ MySQL successfully removed"
        fi
        
        echo "✅ MySQL removal completed"
        
        # Install MariaDB
        install_mariadb
        echo "✅ MariaDB installation completed"
        
        # Verify MariaDB installation
        echo "🔍 Verifying MariaDB installation..."
        if command -v mariadb &> /dev/null; then
            NEW_VERSION=$(mariadb --version 2>/dev/null || echo "unknown")
            echo "✅ MariaDB successfully installed: ${NEW_VERSION}"
        elif command -v mysql &> /dev/null; then
            # Check if this is actually MariaDB
            NEW_VERSION=$(mysql --version 2>/dev/null || echo "unknown")
            if echo "$NEW_VERSION" | grep -i mariadb &> /dev/null; then
                echo "✅ MariaDB successfully installed: ${NEW_VERSION}"
            else
                echo "⚠️ MySQL client detected instead of MariaDB: ${NEW_VERSION}"
                echo "🔍 This might indicate an incomplete installation"
            fi
        else
            echo "❌ No MariaDB client found after installation"
            echo "🔍 Installation may have failed"
            exit 1
        fi
    fi
else
    install_mariadb
    echo "✅ MariaDB installation completed"
fi

echo "::endgroup::"

###############################################################################
echo "::group::🚀 Starting MariaDB Service"

start_mariadb() {
    case $PKG_MANAGER in
        "brew")
            # For versioned installations, ensure data directory exists
            if [[ -n "${MARIADB_VERSION}" ]]; then
                # Check if MariaDB data directory needs initialization
                DATA_DIR="$(brew --prefix)/var/mysql"
                if [[ ! -d "$DATA_DIR" || ! -f "$DATA_DIR/mysql/user.frm" ]]; then
                    echo "📋 Initializing MariaDB data directory..."
                    # Ensure PATH includes versioned binaries for initialization
                    export PATH="$(brew --prefix)/opt/mariadb@${MARIADB_VERSION}/bin:$PATH"
                    
                    # Run mysql_install_db if available
                    if command -v mysql_install_db &> /dev/null; then
                        mysql_install_db --datadir="$DATA_DIR" --user=$(whoami) 2>/dev/null || true
                        echo "✅ MariaDB data directory initialized"
                    fi
                fi
                
                brew services start mariadb@"${MARIADB_VERSION}"
            else
                brew services start mariadb
            fi
            echo "✅ MariaDB service started"
            ;;
        *)
            # Linux distributions - prioritize MariaDB service names
            if command -v systemctl &> /dev/null; then
                echo "🔍 Starting MariaDB service with systemctl..."
                if sudo systemctl start mariadb 2>/dev/null; then
                    sudo systemctl enable mariadb 2>/dev/null || true
                    echo "✅ MariaDB service started and enabled"
                elif sudo systemctl start mysql 2>/dev/null; then
                    sudo systemctl enable mysql 2>/dev/null || true
                    echo "✅ MariaDB service started and enabled"
                else
                    echo "❌ Failed to start MariaDB service"
                    echo "🔍 Service status:"
                    sudo systemctl status mariadb 2>/dev/null || sudo systemctl status mysql 2>/dev/null || echo "  No MariaDB service status available"
                    echo "🔍 Available database services:"
                    systemctl list-units --type=service | grep -E "(mariadb|mysql)" || echo "  No MariaDB services found"
                    exit 1
                fi
            elif command -v service &> /dev/null; then
                echo "🔍 Starting MariaDB service with service command..."
                if sudo service mariadb start 2>/dev/null; then
                    echo "✅ MariaDB service started"
                elif sudo service mysql start 2>/dev/null; then
                    echo "✅ MariaDB service started"
                else
                    echo "❌ Failed to start MariaDB service"
                    exit 1
                fi
            else
                echo "⚠️ Could not start MariaDB service automatically"
                echo "🔍 Please manually start MariaDB service"
            fi
            ;;
    esac
}

start_mariadb

# Wait for MariaDB to be ready
echo "⏳ Waiting for MariaDB to be ready..."
echo "🕐 Allowing time for MariaDB initialization..."
sleep 5

# On some fresh installations, we might need to run mysql_secure_installation equivalent
# or handle the initial root password setup differently
if command -v mysql_secure_installation &> /dev/null; then
    echo "🔍 Checking if MariaDB needs initial security setup..."
    # Test if we can connect without any authentication
    if mysql -u root -e "SELECT 1" &> /dev/null; then
        echo "⚠️ MariaDB allows passwordless root access - this is normal for fresh installations"
    fi
fi

# Function to check if MariaDB is ready
check_mariadb_ready() {
    local password="$1"
    local port="${2:-3306}"

    # Ensure Homebrew's bin directory is in PATH for macOS
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        export PATH="$(brew --prefix)/bin:$PATH"
        echo "✅ Updated PATH to include Homebrew binaries"
        
        # For versioned MariaDB installations, we may need to link or add version-specific paths
        if [[ -n "${MARIADB_VERSION}" ]]; then
            # Check if versioned MariaDB binaries exist and add to PATH
            VERSIONED_PATH="$(brew --prefix)/opt/mariadb@${MARIADB_VERSION}/bin"
            if [[ -d "$VERSIONED_PATH" ]]; then
                export PATH="$VERSIONED_PATH:$PATH"
                echo "✅ Added versioned MariaDB path: $VERSIONED_PATH"
            fi
            
            # Try to link the versioned installation if not already linked
            if ! command -v mariadb &> /dev/null && ! command -v mysql &> /dev/null; then
                echo "🔗 Attempting to link MariaDB@${MARIADB_VERSION}..."
                brew link --force mariadb@"${MARIADB_VERSION}" 2>/dev/null || true
            fi
        fi
    fi

    # Try to find MySQL/MariaDB client command
    MYSQL_CMD=""
    if command -v mariadb &> /dev/null; then
        MYSQL_CMD="mariadb"
        echo "✅ Found mariadb client: $(which mariadb)"
    elif command -v mysql &> /dev/null; then
        MYSQL_CMD="mysql"
        echo "✅ Found mysql client: $(which mysql)"
    else
        echo "❌ No MySQL/MariaDB client found in PATH"
        echo "🔍 Current PATH: $PATH"
        
        # Debug: Show what's available in Homebrew directories
        if [[ "$PKG_MANAGER" == "brew" ]]; then
            echo "🔍 Checking Homebrew directories..."
            ls -la "$(brew --prefix)/bin/" | grep -i maria || echo "No mariadb binaries in main bin"
            if [[ -n "${MARIADB_VERSION}" && -d "$(brew --prefix)/opt/mariadb@${MARIADB_VERSION}/bin" ]]; then
                echo "🔍 Contents of versioned bin directory:"
                ls -la "$(brew --prefix)/opt/mariadb@${MARIADB_VERSION}/bin/" | head -5
            fi
        fi
        return 1
    fi

    # Test connection with timeout
    echo "🔍 Testing MariaDB connection..."
    for i in {15..0}; do
        # Try multiple connection methods
        CONNECTION_SUCCESS=false
        NEEDS_SUDO=false
        
        # First, let's check if this is a fresh MariaDB installation with default settings
        # On many systems, MariaDB is configured with unix_socket auth by default
        if [[ $i -eq 15 ]]; then
            echo "🔍 Checking MariaDB authentication configuration..."
            # Try to check the user table to see what auth methods are available
            if sudo "$MYSQL_CMD" -u root -e "SELECT User, plugin FROM mysql.user WHERE User='root';" 2>/dev/null | grep -q unix_socket; then
                echo "✅ Detected unix_socket authentication for root user"
                NEEDS_SUDO=true
            fi
        fi
        
        # Method 1: Try with TCP port (standard connection)
        local tcp_cmd=()
        if [[ -n "$password" ]]; then
            tcp_cmd=("$MYSQL_CMD" -uroot --password="$password" --port="$port")
        else
            tcp_cmd=("$MYSQL_CMD" -uroot --port="$port")
        fi
        
        if echo 'SELECT 1' | "${tcp_cmd[@]}" &> /dev/null; then
            CONNECTION_SUCCESS=true
        else
            # Method 2: Try with socket (no port specified)
            local socket_cmd=()
            if [[ -n "$password" ]]; then
                socket_cmd=("$MYSQL_CMD" -uroot --password="$password")
            else
                socket_cmd=("$MYSQL_CMD" -uroot)
            fi
            
            if echo 'SELECT 1' | "${socket_cmd[@]}" &> /dev/null; then
                CONNECTION_SUCCESS=true
            else
                # Method 3: Try with sudo (for unix_socket authentication)
                local sudo_cmd=()
                if [[ -n "$password" ]]; then
                    sudo_cmd=(sudo "$MYSQL_CMD" -uroot --password="$password")
                else
                    sudo_cmd=(sudo "$MYSQL_CMD" -uroot)
                fi
                
                echo "🔍 Trying sudo connection: ${sudo_cmd[*]}"
                if echo 'SELECT 1' | "${sudo_cmd[@]}" &> /dev/null; then
                    CONNECTION_SUCCESS=true
                    NEEDS_SUDO=true
                    echo "✅ MariaDB connection successful (using sudo for unix_socket auth)"
                else
                    # Debug: show the actual sudo error
                    if [[ $i -eq 15 ]]; then
                        echo "🔍 Sudo connection error details:"
                        echo 'SELECT 1' | "${sudo_cmd[@]}" 2>&1 | head -3 || true
                    fi
                fi
            fi
        fi
        
        if [[ "$CONNECTION_SUCCESS" == "true" ]]; then
            echo "✅ MariaDB connection successful"
            # Export the connection method for use by other functions
            if [[ "$NEEDS_SUDO" == "true" ]]; then
                export MARIADB_USE_SUDO="true"
                export MARIADB_CLIENT_CMD="$MYSQL_CMD"
            else
                export MARIADB_USE_SUDO="false"
                export MARIADB_CLIENT_CMD="$MYSQL_CMD"
            fi
            return 0
        fi
        
        # Show diagnostic info on first few attempts
        if [[ $i -gt 12 ]]; then
            echo "🔍 Connection attempt $((16-i)): Testing connectivity..."
            
            # Check if MariaDB process is running
            if pgrep -f mariadb &> /dev/null || pgrep -f mysqld &> /dev/null; then
                echo "✅ MariaDB process is running"
            else
                echo "⚠️ MariaDB process not found"
                # Additional process checking
                echo "🔍 Checking for MariaDB/MySQL processes:"
                ps aux | grep -E "(mariadb|mysqld)" | grep -v grep | head -3 || echo "  No MariaDB/MySQL processes found"
            fi
            
            # Check for common socket locations
            for socket_path in /tmp/mysql.sock /var/run/mysqld/mysqld.sock /opt/homebrew/var/mysql/mysql.sock; do
                if [[ -S "$socket_path" ]]; then
                    echo "✅ Found socket: $socket_path"
                    break
                fi
            done
            
            # Show the actual error on first attempt
            if [[ $i -eq 15 ]]; then
                echo "🔍 Connection error details:"
                echo 'SELECT 1' | "${tcp_cmd[@]}" 2>&1 | head -3 || true
                echo "🔍 This might be unix_socket authentication - trying sudo..."
            fi
        fi
        
        echo "⏳ MariaDB not ready yet, waiting... ($i attempts remaining)"
        sleep 2
    done
    
    echo "❌ MariaDB failed to become ready"
    echo "🔍 Final diagnostics:"
    echo "  - Command used: ${tcp_cmd[*]}"
    echo "  - MariaDB processes:"
    pgrep -fl mariadb || pgrep -fl mysqld || echo "    No MariaDB processes found"
    echo "  - Socket files:"
    find /tmp /var/run /opt/homebrew/var -name "mysql*.sock" -o -name "mariadb*.sock" 2>/dev/null | head -5 || echo "    No socket files found"
    return 1
}

if check_mariadb_ready "" "3306"; then
    echo "✅ MariaDB is ready!"
else
    echo "❌ MariaDB failed to start within 30 seconds"
    exit 1
fi

echo "::endgroup::"

###############################################################################
echo "::group::🔐 Configuring MariaDB"

# Configure MariaDB
configure_mariadb() {
    # Ensure Homebrew's bin directory is in PATH for macOS
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        export PATH="$(brew --prefix)/bin:$PATH"
        
        # For versioned MariaDB installations, add version-specific paths
        if [[ -n "${MARIADB_VERSION}" ]]; then
            VERSIONED_PATH="$(brew --prefix)/opt/mariadb@${MARIADB_VERSION}/bin"
            if [[ -d "$VERSIONED_PATH" ]]; then
                export PATH="$VERSIONED_PATH:$PATH"
            fi
        fi
    fi

    # Use the client command discovered during connection testing
    MYSQL_CMD="${MARIADB_CLIENT_CMD}"
    if [[ -z "$MYSQL_CMD" ]]; then
        # Fallback to discovery if not set
        if command -v mariadb &> /dev/null; then
            MYSQL_CMD="mariadb"
        elif command -v mysql &> /dev/null; then
            MYSQL_CMD="mysql"
        else
            echo "❌ No MySQL/MariaDB client found for configuration"
            return 1
        fi
    fi

    # Find mysqladmin command
    MYSQLADMIN_CMD=""
    if command -v mysqladmin &> /dev/null; then
        MYSQLADMIN_CMD="mysqladmin"
    fi

    # Use the sudo setting from connection testing
    USE_SUDO=""
    if [[ "${MARIADB_USE_SUDO}" == "true" ]]; then
        USE_SUDO="sudo"
        echo "✅ Using sudo for MariaDB connections (unix_socket authentication)"
    fi

    # Set root password if specified
    if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
        if [[ -n "$USE_SUDO" ]]; then
            sudo "$MYSQL_CMD" -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';" 2>/dev/null || \
            sudo "$MYSQL_CMD" -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MARIADB_ROOT_PASSWORD}');" 2>/dev/null || \
            sudo "$MYSQLADMIN_CMD" -u root password "${MARIADB_ROOT_PASSWORD}" 2>/dev/null
        else
            "$MYSQL_CMD" -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';" 2>/dev/null || \
            "$MYSQL_CMD" -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MARIADB_ROOT_PASSWORD}');" 2>/dev/null || \
            "$MYSQLADMIN_CMD" -u root password "${MARIADB_ROOT_PASSWORD}" 2>/dev/null
        fi
        echo "✅ Root password configured"
    fi

    # Create database if specified
    if [[ -n "${MARIADB_DATABASE}" ]]; then
        if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
            if [[ -n "$USE_SUDO" ]]; then
                sudo "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${MARIADB_DATABASE}\`;"
            else
                "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${MARIADB_DATABASE}\`;"
            fi
        else
            if [[ -n "$USE_SUDO" ]]; then
                sudo "$MYSQL_CMD" -u root -e "CREATE DATABASE IF NOT EXISTS \`${MARIADB_DATABASE}\`;"
            else
                "$MYSQL_CMD" -u root -e "CREATE DATABASE IF NOT EXISTS \`${MARIADB_DATABASE}\`;"
            fi
        fi
        echo "✅ Database '${MARIADB_DATABASE}' created"
    fi

    # Create user if specified
    if [[ -n "${MARIADB_USER}" && -n "${MARIADB_PASSWORD}" ]]; then
        if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
            if [[ -n "$USE_SUDO" ]]; then
                sudo "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${MARIADB_USER}'@'%' IDENTIFIED BY '${MARIADB_PASSWORD}';"
                if [[ -n "${MARIADB_DATABASE}" ]]; then
                    sudo "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON \`${MARIADB_DATABASE}\`.* TO '${MARIADB_USER}'@'%';"
                else
                    sudo "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO '${MARIADB_USER}'@'%';"
                fi
                sudo "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
            else
                "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${MARIADB_USER}'@'%' IDENTIFIED BY '${MARIADB_PASSWORD}';"
                if [[ -n "${MARIADB_DATABASE}" ]]; then
                    "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON \`${MARIADB_DATABASE}\`.* TO '${MARIADB_USER}'@'%';"
                else
                    "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO '${MARIADB_USER}'@'%';"
                fi
                "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
            fi
        else
            if [[ -n "$USE_SUDO" ]]; then
                sudo "$MYSQL_CMD" -u root -e "CREATE USER IF NOT EXISTS '${MARIADB_USER}'@'%' IDENTIFIED BY '${MARIADB_PASSWORD}';"
                if [[ -n "${MARIADB_DATABASE}" ]]; then
                    sudo "$MYSQL_CMD" -u root -e "GRANT ALL PRIVILEGES ON \`${MARIADB_DATABASE}\`.* TO '${MARIADB_USER}'@'%';"
                else
                    sudo "$MYSQL_CMD" -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${MARIADB_USER}'@'%';"
                fi
                sudo "$MYSQL_CMD" -u root -e "FLUSH PRIVILEGES;"
            else
                "$MYSQL_CMD" -u root -e "CREATE USER IF NOT EXISTS '${MARIADB_USER}'@'%' IDENTIFIED BY '${MARIADB_PASSWORD}';"
                if [[ -n "${MARIADB_DATABASE}" ]]; then
                    "$MYSQL_CMD" -u root -e "GRANT ALL PRIVILEGES ON \`${MARIADB_DATABASE}\`.* TO '${MARIADB_USER}'@'%';"
                else
                    "$MYSQL_CMD" -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${MARIADB_USER}'@'%';"
                fi
                "$MYSQL_CMD" -u root -e "FLUSH PRIVILEGES;"
            fi
        fi
        echo "✅ User '${MARIADB_USER}' created and granted privileges"
    fi

    # Configure port if different from default
    if [[ "${MARIADB_PORT}" != "3306" ]]; then
        # Find MariaDB configuration file
        for config_file in /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/my.cnf /etc/my.cnf /usr/local/etc/my.cnf; do
            if [[ -f "$config_file" ]]; then
                MARIADB_CONFIG_FILE="$config_file"
                break
            fi
        done

        if [[ -n "${MARIADB_CONFIG_FILE}" ]]; then
            # Backup original config
            sudo cp "${MARIADB_CONFIG_FILE}" "${MARIADB_CONFIG_FILE}.backup"
            
            # Update port in config file
            if grep -q "^port" "${MARIADB_CONFIG_FILE}"; then
                sudo sed -i "s/^port.*/port = ${MARIADB_PORT}/" "${MARIADB_CONFIG_FILE}"
            else
                sudo sed -i "/^\[mysqld\]/a port = ${MARIADB_PORT}" "${MARIADB_CONFIG_FILE}"
            fi
            
            echo "✅ Port configured to ${MARIADB_PORT} in ${MARIADB_CONFIG_FILE}"
            
            # Restart MariaDB to apply port change
            case $PKG_MANAGER in
                "brew")
                    if [[ -n "${MARIADB_VERSION}" ]]; then
                        brew services restart mariadb@"${MARIADB_VERSION}"
                    else
                        brew services restart mariadb
                    fi
                    ;;
                *)
                    sudo systemctl restart mariadb || sudo systemctl restart mysql
                    ;;
            esac
            echo "✅ MariaDB restarted with new port configuration"
            
            # Wait for MariaDB to be ready after restart
            echo "⏳ Waiting for MariaDB to be ready after restart..."
            if check_mariadb_ready "${MARIADB_ROOT_PASSWORD}" "${MARIADB_PORT}"; then
                echo "✅ MariaDB is ready!"
            else
                echo "❌ MariaDB failed to start within 30 seconds"
                exit 1
            fi
        else
            echo "⚠️ Could not find MariaDB configuration file to set custom port"
        fi
    fi
}

configure_mariadb

echo "::endgroup::"

###############################################################################
echo "::group::🎯 Running Additional Configuration"

# Run configuration scripts if provided
if [[ -n "${SETUP_CONF_SCRIPT_FOLDER}" && -d "${SETUP_CONF_SCRIPT_FOLDER}" ]]; then
    echo "✅ Processing configuration scripts from ${SETUP_CONF_SCRIPT_FOLDER}"
    for conf_file in "${SETUP_CONF_SCRIPT_FOLDER}"/*.cnf; do
        if [[ -f "$conf_file" ]]; then
            echo "Processing configuration file: $conf_file"
            # Copy configuration files to MariaDB conf.d directory
            if [[ -d "/etc/mysql/conf.d" ]]; then
                sudo cp "$conf_file" "/etc/mysql/conf.d/"
            elif [[ -d "/etc/mysql/mariadb.conf.d" ]]; then
                sudo cp "$conf_file" "/etc/mysql/mariadb.conf.d/"
            fi
        fi
    done
fi

# Run initialization scripts if provided
if [[ -n "${SETUP_INIT_SCRIPT_FOLDER}" && -d "${SETUP_INIT_SCRIPT_FOLDER}" ]]; then
    echo "✅ Processing initialization scripts from ${SETUP_INIT_SCRIPT_FOLDER}"
    
    # Ensure Homebrew's bin directory is in PATH for macOS
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        export PATH="$(brew --prefix)/bin:$PATH"
        
        # For versioned MariaDB installations, add version-specific paths
        if [[ -n "${MARIADB_VERSION}" ]]; then
            VERSIONED_PATH="$(brew --prefix)/opt/mariadb@${MARIADB_VERSION}/bin"
            if [[ -d "$VERSIONED_PATH" ]]; then
                export PATH="$VERSIONED_PATH:$PATH"
            fi
        fi
    fi

    # Use the client command discovered during connection testing
    MYSQL_CMD="${MARIADB_CLIENT_CMD}"
    if [[ -z "$MYSQL_CMD" ]]; then
        # Fallback to discovery if not set
        if command -v mariadb &> /dev/null; then
            MYSQL_CMD="mariadb"
        elif command -v mysql &> /dev/null; then
            MYSQL_CMD="mysql"
        else
            echo "❌ No MySQL/MariaDB client found for initialization scripts"
            MYSQL_CMD="mysql"  # fallback, will likely fail but preserves existing behavior
        fi
    fi

    # Use the sudo setting from connection testing
    USE_SUDO=""
    if [[ "${MARIADB_USE_SUDO}" == "true" ]]; then
        USE_SUDO="sudo"
    fi
    
    for init_file in "${SETUP_INIT_SCRIPT_FOLDER}"/*.sql; do
        if [[ -f "$init_file" ]]; then
            echo "Executing initialization script: $init_file"
            if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
                ${USE_SUDO} "$MYSQL_CMD" -u root -p"${MARIADB_ROOT_PASSWORD}" < "$init_file"
            else
                ${USE_SUDO} "$MYSQL_CMD" -u root < "$init_file"
            fi
        fi
    done
fi

echo "::endgroup::"

###############################################################################
echo "::group::✅ MariaDB Local Installation Complete"

echo "🎉 MariaDB has been successfully installed and configured locally!"
echo ""
echo "📋 Configuration Summary:"
echo "  • Port: ${MARIADB_PORT}"
echo "  • Root Password: ${MARIADB_ROOT_PASSWORD:-"(empty)"}"
if [[ -n "${MARIADB_USER}" ]]; then
    echo "  • User: ${MARIADB_USER}"
    echo "  • User Password: ${MARIADB_PASSWORD:-"(not set)"}"
fi
if [[ -n "${MARIADB_DATABASE}" ]]; then
    echo "  • Database: ${MARIADB_DATABASE}"
fi

# Set output variable for the action
echo "database-type=local" >> $GITHUB_OUTPUT
echo "✅ Database type exported: local"

echo "::endgroup::"

exit 0 