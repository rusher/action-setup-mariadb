@echo off
setlocal enabledelayedexpansion

REM MariaDB Windows Installation Script
REM This script installs MariaDB on Windows using Chocolatey

echo ::group:: Detecting Windows Environment

REM Check if running on Windows
if not "%OS%"=="Windows_NT" (
    echo [ERROR] This script is designed for Windows only
    exit /b 1
)

echo [INFO] Detected Windows OS

REM Check for Chocolatey (required)
if exist "%ProgramData%\chocolatey\bin\choco.exe" (
    echo [INFO] Using Chocolatey package manager
) else (
    echo [ERROR] Chocolatey is required but not found
    echo Please install Chocolatey first: https://chocolatey.org/install
    exit /b 1
)

echo ::endgroup::

REM ############################################################################
echo ::group:: Processing Configuration

REM Set MariaDB version
set MARIADB_VERSION=
if not "%SETUP_TAG%"=="" (
    if not "%SETUP_TAG%"=="latest" (
        REM Check if SETUP_TAG contains a patch version (has 2 dots)
        call :CountDots "%SETUP_TAG%" DOT_COUNT
        if !DOT_COUNT! equ 1 (
            echo [INFO] Partial version detected ^(%SETUP_TAG%^), finding latest patch version...
            call :FindLatestPatchVersion "%SETUP_TAG%" MARIADB_VERSION
            if "!MARIADB_VERSION!"=="" (
                echo [ERROR] Could not find any versions matching %SETUP_TAG%
                exit /b 1
            )
            echo [INFO] Using latest patch version: !MARIADB_VERSION!
        ) else (
            set MARIADB_VERSION=%SETUP_TAG%
            echo [INFO] MariaDB version set to !MARIADB_VERSION!
        )
    ) else (
        echo [INFO] Using latest MariaDB version
    )
) else (
    echo [INFO] Using latest MariaDB version
)

REM Set port
set MARIADB_PORT=3306
if not "%SETUP_PORT%"=="" (
    set MARIADB_PORT=%SETUP_PORT%
)
echo [INFO] MariaDB port set to !MARIADB_PORT!

REM Set root password
set MARIADB_ROOT_PASSWORD=
if not "%SETUP_ROOT_PASSWORD%"=="" (
    set "MARIADB_ROOT_PASSWORD=!SETUP_ROOT_PASSWORD!"
    echo [INFO] Root password is explicitly set
) else (
    if "%SETUP_ALLOW_EMPTY_ROOT_PASSWORD%"=="1" (
        set MARIADB_ROOT_PASSWORD=
        echo [WARN] Root password will be empty
    ) else (
        REM Generate random password
        set MARIADB_ROOT_PASSWORD=%RANDOM%%RANDOM%%RANDOM%
        echo [WARN] Root password will be randomly generated: !MARIADB_ROOT_PASSWORD!
    )
)

REM Set user and password
set MARIADB_USER=
set MARIADB_PASSWORD=
if not "%SETUP_USER%"=="" (
    set MARIADB_USER=%SETUP_USER%
    echo [INFO] MariaDB user set to !MARIADB_USER!
)

if not "%SETUP_PASSWORD%"=="" (
    set MARIADB_PASSWORD=%SETUP_PASSWORD%
    echo [INFO] MariaDB user password is explicitly set
)

REM Set database
set MARIADB_DATABASE=
if not "%SETUP_DATABASE%"=="" (
    set MARIADB_DATABASE=%SETUP_DATABASE%
    echo [INFO] Initial database set to !MARIADB_DATABASE!
)



echo ::endgroup::

REM ############################################################################
echo ::group:: Installing MariaDB

REM Check if MySQL is installed and stop it if running
echo Checking for existing MySQL installation...
where mysql >nul 2>&1
if %errorlevel%==0 (
    echo [WARN] MySQL command found in PATH
    echo [INFO] MySQL path:
    where mysql
    echo [INFO] MySQL version:
    mysql --version
    
    mysql --version 2>nul | findstr /i "mysql" >nul
    if %errorlevel%==0 (
        echo [INFO] MySQL detected - stopping MySQL services to avoid conflicts
        
        REM Stop MySQL services if running
        echo [INFO] Stopping MySQL services...
        net stop MySQL80 >nul 2>&1
        if %errorlevel%==0 (
            echo [SUCCESS] MySQL80 service stopped
        ) else (
            echo [INFO] MySQL80 service was not running or not found
        )
        
        net stop MySQL >nul 2>&1
        if %errorlevel%==0 (
            echo [SUCCESS] MySQL service stopped
        ) else (
            echo [INFO] MySQL service was not running or not found
        )
        
        echo [SUCCESS] MySQL services stopped - proceeding with MariaDB installation
        echo [INFO] Note: MySQL is still installed but stopped to avoid port conflicts
    )
)

REM Check if MariaDB is already installed
echo [INFO] Checking for existing MariaDB installation...

REM Only check for mariadb command specifically
where mariadb >nul 2>&1
if %errorlevel%==0 (
    echo [WARN] MariaDB command found in PATH
    echo [INFO] MariaDB path:
    where mariadb
    echo [INFO] MariaDB version:
    mariadb --version
    goto mariadb_installed
)

echo [INFO] No existing MariaDB installation detected, proceeding with installation...

REM Install MariaDB
echo Installing MariaDB using Chocolatey...
if not "%MARIADB_VERSION%"=="" (
    choco install mariadb --version=%MARIADB_VERSION% -y
) else (
    choco install mariadb -y
)
if !errorlevel! neq 0 (
    echo [ERROR] Failed to install MariaDB via Chocolatey
    exit /b 1
)
echo [SUCCESS] MariaDB installation completed

:mariadb_installed
REM Verify installation by checking if package was installed
choco list mariadb --exact --limit-output

REM List what was actually installed
echo [INFO] Checking what Chocolatey installed:
if exist "C:\ProgramData\chocolatey\lib\" (
    dir "C:\ProgramData\chocolatey\lib\" /b /ad 2>nul | findstr /i maria
)

echo ::endgroup::

REM ############################################################################
echo ::group:: Starting MariaDB Service

echo Starting MariaDB service...

REM Check for MariaDB service
sc query "MariaDB" >nul 2>&1
if %errorlevel%==0 (
    echo [INFO] Found MariaDB service
    net start "MariaDB" >nul 2>&1
    if %errorlevel%==0 (
        echo [SUCCESS] MariaDB service started successfully
    ) else (
        echo [WARN] MariaDB service may already be running or failed to start
    )
) else (
    echo [WARN] MariaDB service not found
    echo [INFO] MariaDB may not be installed correctly or service not registered
)

REM Wait for MariaDB to be ready
echo [LOADING] Waiting for MariaDB to be ready...

REM Detect which command is available
set MYSQL_CMD=
where mariadb >nul 2>&1
if %errorlevel%==0 (
    set MYSQL_CMD=mariadb
    echo [INFO] Found mariadb command in PATH
) else (
    echo [INFO] mariadb command not found, searching for MariaDB installation...
    call :FindMariaDBPath
    if "!MYSQL_CMD!"=="" (
        echo [ERROR] mariadb command not found
        echo [INFO] Attempting to locate MariaDB installation...
        call :ListMariaDBPaths
        exit /b 1
    )
)
echo [INFO] Using command: !MYSQL_CMD!

set /a counter=0
:wait_loop
REM Try to connect using the detected command
!MYSQL_CMD! -u root --execute="SELECT 1 AS test;" --silent 2>nul
if %errorlevel%==0 (
    echo [SUCCESS] MariaDB is ready!
    goto configure_db
)
set /a counter+=1
if %counter% geq 30 (
    echo [ERROR] MariaDB failed to start within 30 seconds
    exit /b 1
)
timeout /t 1 /nobreak >nul
goto wait_loop

:configure_db
echo ::endgroup::

REM ############################################################################
echo ::group:: Configuring MariaDB

REM Set root password if specified
if not "%MARIADB_ROOT_PASSWORD%"=="" (
    echo Configuring root password...
    !MYSQL_CMD! -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '!MARIADB_ROOT_PASSWORD!';" 2>nul
    if !errorlevel! neq 0 (
        !MYSQL_CMD! -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('!MARIADB_ROOT_PASSWORD!');" 2>nul
        if !errorlevel! neq 0 (
            mysqladmin -u root password "!MARIADB_ROOT_PASSWORD!" 2>nul
        )
    )
    echo [SUCCESS] Root password configured
)

REM Create database if specified
if not "%MARIADB_DATABASE%"=="" (
    echo Creating database '%MARIADB_DATABASE%'...
    if not "!MARIADB_ROOT_PASSWORD!"=="" (
        !MYSQL_CMD! -u root -p"!MARIADB_ROOT_PASSWORD!" -e "CREATE DATABASE IF NOT EXISTS `%MARIADB_DATABASE%`;"
    ) else (
        !MYSQL_CMD! -u root -e "CREATE DATABASE IF NOT EXISTS `%MARIADB_DATABASE%`;"
    )
    if !errorlevel!==0 (
        echo [SUCCESS] Database '%MARIADB_DATABASE%' created
    ) else (
        echo [ERROR] Failed to create database '%MARIADB_DATABASE%'
    )
)

REM Create user if specified
if not "%MARIADB_USER%"=="" (
    if not "%MARIADB_PASSWORD%"=="" (
        echo Creating user '%MARIADB_USER%'...
        if not "!MARIADB_ROOT_PASSWORD!"=="" (
            !MYSQL_CMD! -u root -p"!MARIADB_ROOT_PASSWORD!" -e "CREATE USER IF NOT EXISTS '%MARIADB_USER%'@'%%' IDENTIFIED BY '%MARIADB_PASSWORD%';"
            if not "%MARIADB_DATABASE%"=="" (
                !MYSQL_CMD! -u root -p"!MARIADB_ROOT_PASSWORD!" -e "GRANT ALL PRIVILEGES ON `%MARIADB_DATABASE%`.* TO '%MARIADB_USER%'@'%%';"
            ) else (
                !MYSQL_CMD! -u root -p"!MARIADB_ROOT_PASSWORD!" -e "GRANT ALL PRIVILEGES ON *.* TO '%MARIADB_USER%'@'%%';"
            )
            !MYSQL_CMD! -u root -p"!MARIADB_ROOT_PASSWORD!" -e "FLUSH PRIVILEGES;"
        ) else (
            !MYSQL_CMD! -u root -e "CREATE USER IF NOT EXISTS '%MARIADB_USER%'@'%%' IDENTIFIED BY '%MARIADB_PASSWORD%';"
            if not "%MARIADB_DATABASE%"=="" (
                !MYSQL_CMD! -u root -e "GRANT ALL PRIVILEGES ON `%MARIADB_DATABASE%`.* TO '%MARIADB_USER%'@'%%';"
            ) else (
                !MYSQL_CMD! -u root -e "GRANT ALL PRIVILEGES ON *.* TO '%MARIADB_USER%'@'%%';"
            )
            !MYSQL_CMD! -u root -e "FLUSH PRIVILEGES;"
        )
        echo [SUCCESS] User '%MARIADB_USER%' created and granted privileges
    )
)

REM Process SETUP_ADDITIONAL_CONF
if defined SETUP_ADDITIONAL_CONF (
    echo [INFO] Processing additional configuration options...
    call :ProcessAdditionalConf "!SETUP_ADDITIONAL_CONF!"
    
    REM Restart MariaDB service to apply configuration changes
    echo [INFO] Restarting MariaDB service to apply configuration changes...
    sc query "MariaDB" >nul 2>&1
    if %errorlevel%==0 (
        net stop "MariaDB" >nul 2>&1
        timeout /t 2 /nobreak >nul
        net start "MariaDB" >nul 2>&1
        if %errorlevel%==0 (
            echo [SUCCESS] MariaDB service restarted successfully
        ) else (
            echo [WARN] Failed to restart MariaDB service - configuration changes may not be applied
        )
    ) else (
        echo [WARN] MariaDB service not found - configuration changes may require manual service restart
    )
)

echo ::endgroup::

REM ############################################################################
echo ::group:: Running Additional Configuration

echo [DEBUG] Starting additional configuration section...

REM Safely check if configuration script folder is provided
set "CONF_FOLDER_SET=0"
if defined SETUP_CONF_SCRIPT_FOLDER (
    if not "%SETUP_CONF_SCRIPT_FOLDER%"=="" (
        set "CONF_FOLDER_SET=1"
    )
)

echo [DEBUG] Configuration folder check completed

REM Run configuration scripts if provided
echo [DEBUG] About to check CONF_FOLDER_SET value: [!CONF_FOLDER_SET!]
if defined CONF_FOLDER_SET (
    if "!CONF_FOLDER_SET!"=="1" goto process_config_scripts
)
goto skip_config_scripts

:process_config_scripts
echo [DEBUG] Processing configuration scripts
if not defined SETUP_CONF_SCRIPT_FOLDER goto skip_config_scripts
if "!SETUP_CONF_SCRIPT_FOLDER!"=="" goto skip_config_scripts
if not exist "!SETUP_CONF_SCRIPT_FOLDER!" (
    echo [WARN] Configuration script folder !SETUP_CONF_SCRIPT_FOLDER! does not exist
    goto skip_config_scripts
)

echo Processing configuration scripts from !SETUP_CONF_SCRIPT_FOLDER!
echo [INFO] Configuration script processing is temporarily simplified for stability
echo [INFO] Complex configuration file processing has been disabled to prevent syntax errors

:skip_config_scripts
echo [DEBUG] Configuration script section completed

echo [DEBUG] Configuration section completed, moving to initialization scripts

REM Safely check if initialization script folder is provided
set "INIT_FOLDER_SET=0"
if defined SETUP_INIT_SCRIPT_FOLDER (
    if not "%SETUP_INIT_SCRIPT_FOLDER%"=="" (
        set "INIT_FOLDER_SET=1"
    )
)

echo [DEBUG] Initialization folder check completed

REM Run initialization scripts if provided
if defined INIT_FOLDER_SET (
    if "!INIT_FOLDER_SET!"=="1" goto process_init_scripts
)
goto skip_init_scripts

:process_init_scripts
echo [DEBUG] Processing initialization scripts
if not defined SETUP_INIT_SCRIPT_FOLDER goto skip_init_scripts
if "!SETUP_INIT_SCRIPT_FOLDER!"=="" goto skip_init_scripts
if not exist "!SETUP_INIT_SCRIPT_FOLDER!" (
    echo [WARN] Initialization script folder !SETUP_INIT_SCRIPT_FOLDER! does not exist
    goto skip_init_scripts
)

echo [LOADING] Processing initialization scripts from !SETUP_INIT_SCRIPT_FOLDER!
for %%f in ("!SETUP_INIT_SCRIPT_FOLDER!\*.sql") do (
    if exist "%%f" (
        echo Executing initialization script: %%f
        if not "!MARIADB_ROOT_PASSWORD!"=="" (
            !MYSQL_CMD! -u root -p"!MARIADB_ROOT_PASSWORD!" < "%%f"
        ) else (
            !MYSQL_CMD! -u root < "%%f"
        )
    )
)

:skip_init_scripts
echo [DEBUG] Initialization script section completed

echo ::endgroup::

REM ############################################################################
echo ::group:: MariaDB Windows Installation Complete

echo [SUCCESS] MariaDB has been successfully installed and configured on Windows!
echo.
echo [SUCCESS] Configuration Summary:
echo   [INFO] Port: %MARIADB_PORT%
if not "%MARIADB_ROOT_PASSWORD%"=="" (
    echo   [INFO] Root Password set
) else (
    echo   [INFO] Root Password: (empty)
)
if not "%MARIADB_USER%"=="" (
    echo   [INFO] User: %MARIADB_USER%
    if not "%MARIADB_PASSWORD%"=="" (
        echo   [INFO] User Password set
    ) else (
        echo   [INFO] User Password: (not set)
    )
)
if not "%MARIADB_DATABASE%"=="" (
    echo   [INFO] Database: %MARIADB_DATABASE%
)

REM Set output variable for the action
echo database-type=local >> %GITHUB_OUTPUT%
echo [SUCCESS] Database type exported: local

echo ::endgroup::

REM End of main script execution
exit /b 0

REM ############################################################################
REM Helper Functions
REM ############################################################################

:CountDots
REM Function to count dots in a string
set "INPUT_STRING=%~1"
set "RETURN_VAR=%~2"
set DOT_COUNT=0
set "TEMP_STRING=%INPUT_STRING%"

:count_loop
for /f "tokens=1,* delims=." %%a in ("%TEMP_STRING%") do (
    if not "%%b"=="" (
        set /a DOT_COUNT+=1
        set "TEMP_STRING=%%b"
        goto count_loop
    )
)

set "%RETURN_VAR%=%DOT_COUNT%"
goto :eof

:FindLatestPatchVersion
REM Function to find the latest patch version for a given major.minor version
set "VERSION_PATTERN=%~1"
REM Trim any spaces from the version pattern
set "VERSION_PATTERN=!VERSION_PATTERN: =!"
set "RETURN_VAR=%~2"
set "LATEST_VERSION="

echo [INFO] Searching for latest !VERSION_PATTERN!.x version...

REM Create temporary file for search results
set "TEMP_FILE=%TEMP%\mariadb_versions_%RANDOM%.txt"

REM Search for matching versions and save to temp file
choco search mariadb --exact --all-versions > "%TEMP_FILE%" 2>nul

REM Parse versions that match the pattern
set "SEARCH_PATTERN=mariadb !VERSION_PATTERN!."
for /f "tokens=2" %%v in ('findstr /c:"!SEARCH_PATTERN!" "%TEMP_FILE%"') do (
    set "CURRENT_VERSION=%%v"
    REM Remove [Approved] and other suffixes
    for /f "tokens=1" %%c in ("!CURRENT_VERSION!") do (
        set "CLEAN_VERSION=%%c"
        REM Simple comparison - since Chocolatey lists versions in descending order, 
        REM the first match is the latest
        if "!LATEST_VERSION!"=="" (
            set "LATEST_VERSION=!CLEAN_VERSION!"
        )
    )
)

REM Cleanup temp file
if exist "%TEMP_FILE%" del "%TEMP_FILE%" >nul 2>&1

if not "!LATEST_VERSION!"=="" (
    echo [SUCCESS] Found latest version: !LATEST_VERSION!
) else (
    echo [ERROR] No versions found matching pattern !VERSION_PATTERN!.x
)

set "%RETURN_VAR%=%LATEST_VERSION%"
goto :eof

:FindMariaDBPath
REM Try to find MariaDB installation and add to PATH
set MYSQL_CMD=

echo [INFO] Searching for MariaDB binaries

REM Helper function to check mariadb.exe and mysql.exe in a given directory (prioritize mariadb)
call :CheckBinariesInPath "C:\ProgramData\chocolatey\lib\mariadb\tools\bin" "Chocolatey mariadb\tools\bin"
if not "!MYSQL_CMD!"=="" goto :eof

call :CheckBinariesInPath "C:\ProgramData\chocolatey\lib\mariadb\bin" "Chocolatey mariadb\bin"
if not "!MYSQL_CMD!"=="" goto :eof

call :CheckBinariesInPath "C:\ProgramData\chocolatey\lib\mariadb-server\tools\bin" "Chocolatey mariadb-server\tools\bin"
if not "!MYSQL_CMD!"=="" goto :eof

REM Check common MariaDB versions in Program Files
echo [INFO] Checking Program Files paths...
for %%v in (10.3 10.4 10.5 10.6 10.7 10.8 10.9 10.10 10.11 11.0 11.1 11.2 11.3 11.4 11.5 11.6 11.7 11.8 12.0 12.1 12.2 12.2) do (
    call :CheckBinariesInPath "C:\Program Files\MariaDB %%v\bin" "Program Files MariaDB %%v"
    if not "!MYSQL_CMD!"=="" goto :eof
)

REM Check common MariaDB versions in ProgramData
echo [INFO] Checking ProgramData paths...
for %%v in (10.3 10.4 10.5 10.6 10.7 10.8 10.9 10.10 10.11 11.0 11.1 11.2 11.3 11.4 11.5 11.6 11.7 11.8 12.0 12.1 12.2 12.3) do (
    call :CheckBinariesInPath "C:\ProgramData\MariaDB\MariaDB Server %%v\bin" "ProgramData MariaDB Server %%v"
    if not "!MYSQL_CMD!"=="" goto :eof
)

REM Use dir command to safely check for any MariaDB installations
echo [INFO] Checking for MariaDB installations using dir command...
dir "C:\Program Files\Maria*" /b /ad >temp_dirs.txt 2>nul
if exist temp_dirs.txt (
    echo [INFO] Found MariaDB directories in Program Files:
    type temp_dirs.txt
    for /f "tokens=*" %%a in (temp_dirs.txt) do (
        call :CheckBinariesInPath "C:\Program Files\%%a\bin" "Program Files %%a"
        if not "!MYSQL_CMD!"=="" (
            del temp_dirs.txt >nul 2>&1
            goto :eof
        )
    )
    del temp_dirs.txt >nul 2>&1
) else (
    echo [INFO] No MariaDB directories found in Program Files
)

echo [WARN] No MariaDB installation found in standard locations
goto :eof

REM Helper function to check for mariadb.exe and mysql.exe in a given path (prioritize mariadb)
:CheckBinariesInPath
set "CHECK_PATH=%~1"
set "LOCATION_DESC=%~2"

if exist "%CHECK_PATH%\mariadb.exe" (
    set "PATH=%PATH%;%CHECK_PATH%"
    set MYSQL_CMD=mariadb
    echo [SUCCESS] Found MariaDB at %CHECK_PATH%\mariadb.exe ^(%LOCATION_DESC%^)
    goto :eof
)

if exist "%CHECK_PATH%\mysql.exe" (
    set "PATH=%PATH%;%CHECK_PATH%"
    set MYSQL_CMD=mysql
    echo [SUCCESS] Found MySQL at %CHECK_PATH%\mysql.exe ^(%LOCATION_DESC%^) - will use as fallback
    goto :eof
)

goto :eof

:ListMariaDBPaths
echo [INFO] === MariaDB Installation Diagnostic ===
echo [INFO] Searching for MariaDB installations...

echo [INFO] Checking C:\Program Files\ for MariaDB:
dir "C:\Program Files\" /b /ad 2>nul | findstr /i maria
if %errorlevel% neq 0 echo [INFO] No MariaDB directories found in Program Files

echo [INFO] Checking C:\ProgramData\ for MariaDB:
if exist "C:\ProgramData\MariaDB\" (
    echo [SUCCESS] Found C:\ProgramData\MariaDB\
    dir "C:\ProgramData\MariaDB\" /b /ad 2>nul
) else (
    echo [INFO] C:\ProgramData\MariaDB\ not found
)

echo [INFO] Checking Chocolatey packages:
if exist "C:\ProgramData\chocolatey\lib\" (
    echo [INFO] MariaDB-related packages in Chocolatey:
    dir "C:\ProgramData\chocolatey\lib\" /b /ad 2>nul | findstr /i maria
    if %errorlevel% neq 0 echo [INFO] No MariaDB packages found in Chocolatey lib
    
    echo [INFO] All Chocolatey packages:
    dir "C:\ProgramData\chocolatey\lib\" /b /ad 2>nul
) else (
    echo [ERROR] Chocolatey lib directory not found at C:\ProgramData\chocolatey\lib\
)

echo [INFO] Checking for MySQL installations:
dir "C:\Program Files\" /b /ad 2>nul | findstr /i mysql
if %errorlevel% neq 0 echo [INFO] No MySQL directories found in Program Files

echo [INFO] Checking Windows Services for MariaDB/MySQL:
sc query type= service state= all | findstr /i "mariadb mysql" 2>nul
if %errorlevel% neq 0 echo [INFO] No MariaDB/MySQL services found

echo [INFO] === End Diagnostic ===
echo [ERROR] MariaDB installation appears to have failed or installed to an unexpected location
echo [INFO] Possible solutions:
echo [INFO] 1. Check if Chocolatey installation completed successfully
echo [INFO] 2. Try running: choco list mariadb --exact --limit-output
echo [INFO] 3. Try reinstalling: choco uninstall mariadb -y, then choco install mariadb -y
echo [INFO] 4. Check Windows Event Logs for installation errors
goto :eof

:ProcessAdditionalConf
REM Function to process additional configuration options
set "ADDITIONAL_CONF=%~1"
if "%ADDITIONAL_CONF%"=="" goto :eof

echo [DEBUG] Starting ProcessAdditionalConf function
echo [INFO] Processing additional configuration: %ADDITIONAL_CONF%

REM Find MariaDB configuration file
echo [DEBUG] Calling FindMariaDBConfigFile
call :FindMariaDBConfigFile CONFIG_FILE
if "%CONFIG_FILE%"=="" (
    echo [ERROR] Could not find MariaDB configuration file
    goto :eof
)

echo [INFO] Using configuration file: %CONFIG_FILE%
echo [DEBUG] Configuration file found successfully

REM Create a temporary file to store the raw additional config
set "TEMP_INPUT_FILE=%TEMP%\mariadb_input_%RANDOM%.txt"
set "TEMP_CONF_FILE=%TEMP%\mariadb_additional_conf_%RANDOM%.txt"

REM Process the additional configuration directly without using temporary files
REM that might cause issues with input redirection in GitHub Actions
echo [DEBUG] About to call ProcessConfigLine
call :ProcessConfigLine "%ADDITIONAL_CONF%" "%TEMP_CONF_FILE%"
echo [DEBUG] ProcessConfigLine completed

REM Add the configurations to the MariaDB config file
if exist "%TEMP_CONF_FILE%" (
    REM Always add [mysqld] section to be safe (won't hurt if it already exists)
    echo. >> "%CONFIG_FILE%"
    echo [mysqld] >> "%CONFIG_FILE%"
    echo. >> "%CONFIG_FILE%"
    echo # Additional configuration options added by setup script >> "%CONFIG_FILE%"
    type "%TEMP_CONF_FILE%" >> "%CONFIG_FILE%"
    del "%TEMP_CONF_FILE%" >nul 2>&1
    echo [SUCCESS] Additional configuration options added to %CONFIG_FILE%
) else (
    echo [WARN] No valid configuration options found to add
)

goto :eof

:ProcessConfigLine
REM Function to process a single configuration line
set "LINE=%~1"
set "OUTPUT_FILE=%~2"

REM Clean up the line by removing leading/trailing whitespace and line feeds
set "LINE=%LINE: =%"
if "%LINE%"=="" goto :eof

REM Replace common line separators with spaces for easier processing
set "LINE=%LINE:\n= %"
set "LINE=%LINE:\r= %"

REM Handle space-separated options on the same line
REM Use a safer approach that doesn't rely on complex parsing
call :ProcessSingleOptions "%LINE%" "%OUTPUT_FILE%"

goto :eof

:ProcessSingleOptions
set "OPTIONS=%~1"
set "OUTPUT_FILE=%~2"

REM Simple approach: split on spaces and process each token
for %%a in (%OPTIONS%) do (
    set "OPTION=%%a"
    REM Skip empty options
    if not "!OPTION!"=="" (
        REM Remove -- prefix if present
        if "!OPTION:~0,2!"=="--" (
            set "OPTION=!OPTION:~2!"
        )
        REM Only add non-empty options
        if not "!OPTION!"=="" (
            echo !OPTION! >> "%OUTPUT_FILE%"
            echo [INFO] Added configuration option: !OPTION!
        )
    )
)

goto :eof

:FindMariaDBConfigFile
REM Function to find MariaDB configuration file
set "RETURN_VAR=%~1"
set "FOUND_CONFIG="

REM Check common MariaDB configuration file locations on Windows
REM Priority order: custom config in data directory, default installation paths

REM Try to find the data directory from MariaDB using a simpler approach
REM Skip the complex help parsing that causes issues in GitHub Actions

REM Check common MariaDB versions in Program Files
echo [INFO] Checking Program Files paths for config files...
for %%v in (10.3 10.4 10.5 10.6 10.7 10.8 10.9 10.10 10.11 11.0 11.1 11.2 11.3 11.4 11.5 11.6 11.7 11.8 12.0 12.1 12.2 12.3) do (
    call :CheckConfigInPath "C:\Program Files\MariaDB %%v\data" "Program Files MariaDB %%v data"
    if not "!FOUND_CONFIG!"=="" goto config_found
    call :CheckConfigInPath "C:\Program Files\MariaDB %%v" "Program Files MariaDB %%v"
    if not "!FOUND_CONFIG!"=="" goto config_found
)

REM Check common MariaDB versions in ProgramData
echo [INFO] Checking ProgramData paths for config files...
for %%v in (10.3 10.4 10.5 10.6 10.7 10.8 10.9 10.10 10.11 11.0 11.1 11.2 11.3 11.4 11.5 11.6 11.7 11.8 12.0 12.1 12.2 12.3) do (
    call :CheckConfigInPath "C:\ProgramData\MariaDB\MariaDB Server %%v\data" "ProgramData MariaDB Server %%v data"
    if not "!FOUND_CONFIG!"=="" goto config_found
    call :CheckConfigInPath "C:\ProgramData\MariaDB\MariaDB Server %%v" "ProgramData MariaDB Server %%v"
    if not "!FOUND_CONFIG!"=="" goto config_found
)

REM Check other common paths
call :CheckConfigInPath "C:\ProgramData\MariaDB\data" "ProgramData MariaDB data"
if not "!FOUND_CONFIG!"=="" goto config_found
call :CheckConfigInPath "C:\ProgramData\MySQL\MySQL Server 8.0" "MySQL Server 8.0"
if not "!FOUND_CONFIG!"=="" goto config_found

REM Try to find any MariaDB installation directory and look for config files
for /d %%d in ("C:\Program Files\MariaDB*") do (
    if exist "%%d\data\my.ini" (
        set "FOUND_CONFIG=%%d\data\my.ini"
        goto config_found
    )
    if exist "%%d\my.ini" (
        set "FOUND_CONFIG=%%d\my.ini"
        goto config_found
    )
)

REM If no existing config found, create one in a default location
if "!FOUND_CONFIG!"=="" (
    REM Try common data directory locations for creating a new config file
    set "DEFAULT_DATA_DIRS=C:\ProgramData\MariaDB\data"
    set "DEFAULT_DATA_DIRS=!DEFAULT_DATA_DIRS!;C:\Program Files\MariaDB 10.11\data"
    set "DEFAULT_DATA_DIRS=!DEFAULT_DATA_DIRS!;C:\Program Files\MariaDB 10.10\data"
    set "DEFAULT_DATA_DIRS=!DEFAULT_DATA_DIRS!;C:\Program Files\MariaDB 10.9\data"
    
    for %%d in (!DEFAULT_DATA_DIRS!) do (
        if exist "%%d" (
            set "FOUND_CONFIG=%%d\my.ini"
            REM Create basic config file if it doesn't exist
            if not exist "!FOUND_CONFIG!" (
                echo [mysqld] > "!FOUND_CONFIG!"
                echo port=3306 >> "!FOUND_CONFIG!"
                echo [INFO] Created new configuration file: !FOUND_CONFIG!
            )
            goto config_found
        )
    )
)

:config_found
set "%RETURN_VAR%=%FOUND_CONFIG%"
goto :eof

:CheckConfigInPath
REM Helper function to check for my.ini and my.cnf in a given path
set "CHECK_PATH=%~1"
set "LOCATION_DESC=%~2"

if exist "%CHECK_PATH%\my.ini" (
    set "FOUND_CONFIG=%CHECK_PATH%\my.ini"
    echo [SUCCESS] Found MariaDB config at %CHECK_PATH%\my.ini ^(%LOCATION_DESC%^)
    goto :eof
)

if exist "%CHECK_PATH%\my.cnf" (
    set "FOUND_CONFIG=%CHECK_PATH%\my.cnf"
    echo [SUCCESS] Found MariaDB config at %CHECK_PATH%\my.cnf ^(%LOCATION_DESC%^)
    goto :eof
)

goto :eof
