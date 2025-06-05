# MariaDB github action

This action sets up a MariaDB server for the rest of the job. Here are some
key features:

* Runs on linux/Macos/windows runners
* Can use either community, enterprise or development releases

#### Inputs

| Key                       | Description                                                                                                                                   | Default             | Required |
|---------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|---------------------|----------|
| tag                       | Valid image tag from registry                                                                                                                 | `latest`            | No       |
| local                     | Local (native) installation instead of using containers. This might not be respected, since enterprise is only available on docker. check output variable `database-type` is needed                                                                                     |                     | No       |
| port                      | Exposed port for database connections                                                                                                         | 3306                | No       |
| registry                  | registry for MariaDB image (e.g., 'docker.io/mariadb', 'quay.io/mariadb-foundation/mariadb-devel', or 'docker.mariadb.com/enterprise-server') | `docker.io/mariadb` | No       |
| registry-user             | registry username when (mandatory when using enterprise registry)                                                                             |                     | No       |
| registry-password         | registry password when (mandatory when using enterprise registry)                                                                             |                     | No       |
| container-runtime         | Container runtime to use (docker or podman)                                                                                                   | `podman`            | No       |
| root-password             | Password for root user                                                                                                                        |                     | No       |
| allow-empty-root-password | Permits empty root password                                                                                                                   |                     | No       |
| user                      | Create a MariaDB user                                                                                                                         |                     | No       |
| password                  | Define a password for MariaDB user                                                                                                            |                     | No       |
| database                  | Initial database to create                                                                                                                    |                     | No       |
| conf-script-folder        | Additional configuration directory                                                                                                            |                     | No       |
| additional-conf           | Additional configuration                                                                                                                      |                     | No       |
| init-script-folder        | Initialization script directory                                                                                                               |                     | No       |

#### Outputs

| Key           | Description                                                                                         | Values               |
|---------------|-----------------------------------------------------------------------------------------------------|----------------------|
| database-type | Type of database setup used by the action                                                          | `local`, `container` |

- **`local`**: MariaDB is installed natively on the runner (using `setup-local.sh` or `setup-windows.bat`)
- **`container`**: MariaDB is running in a Docker/Podman container (using `setup-docker.sh`)

#### Community server

```yaml
steps:
  - name: Set up MariaDB
    uses: rusher/setup-mariadb@v1
    with:
      tag: '10.6'
      root-password: 'myRootPassword'
      user: 'myUser'
      password: 'MyPassw0rd'
      database: 'myDb'
      additional-conf: '--max_allowed_packet=40M --innodb_log_file_size=400M'
```

#### enterprise

```yaml
steps:
  - name: Set up MariaDB
    uses: rusher/setup-mariadb@v1
    with:
      tag: '10.6'
      registry: 'docker.mariadb.com/enterprise-server'
      registry-user: 'myUser@mail.com'
      registry-password: 'myDockerEnterprisePwd'
      root-password: 'myRootPassword'
      user: 'myUser'
      password: 'MyPassw0rd'
      database: 'myDb' 
```

#### Development

this are development or preview versions 
see tag from https://quay.io/repository/mariadb-foundation/mariadb-devel?tab=tags&tag=latest

```yaml
steps:
  - name: Set up MariaDB
    uses: rusher/setup-mariadb@v1
    with:
      tag: '12.0-preview'
      registry: 'quay.io/mariadb-foundation/mariadb-devel'
      root-password: 'myRootPassword'
      user: 'myUser'
      password: 'MyPassw0rd'
      database: 'myDb' 
```

#### Using Output Variables

You can use the `database-type` output to determine how MariaDB was set up:

```yaml
steps:
  - name: Set up MariaDB
    id: mariadb
    uses: rusher/setup-mariadb@v1
    with:
      tag: '10.6'
      local: true  # Force local installation
      root-password: 'myRootPassword'
      database: 'myDb'
      
  - name: Check database setup type
    run: |
      echo "Database type: ${{ steps.mariadb.outputs.database-type }}"
      if [ "${{ steps.mariadb.outputs.database-type }}" = "local" ]; then
        echo "MariaDB is installed locally on the runner"
        # Add local-specific commands here
      else
        echo "MariaDB is running in a container"
        # Add container-specific commands here
      fi
```

## License

The scripts and documentation in this project are released under the
[MIT License](LICENSE).