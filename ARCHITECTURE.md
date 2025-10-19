# GitLab CE Architecture

## System Overview
GitLab Community Edition deployed as a single Docker container with integrated services, providing Git repository hosting, CI/CD pipelines, container registry, and project management.

## Architecture Diagram
```
                         Users
                           |
                      [HTTPS/SSH]
                           |
                    Traefik Proxy
                    (Port 443/2222)
                           |
                    GitLab Container
                           |
    ┌──────────────────────┼──────────────────────┐
    |                      |                      |
PostgreSQL            Redis Cache            Container Registry
(Internal)            (Internal)              (Port 5050)
    |                      |                      |
    └──────────────────────┼──────────────────────┘
                           |
                    Keycloak SSO
                  (External Auth)
```

## Components

### Core Services (Inside GitLab Container)

#### Puma (Web Server)
- **Purpose**: Handles HTTP requests
- **Port**: 80 (internal)
- **Workers**: Dynamic based on load
- **Memory**: Max 1GB per worker

#### Sidekiq (Background Jobs)
- **Purpose**: Asynchronous task processing
- **Concurrency**: 15 threads
- **Queues**: Default, mailers, pipeline processing
- **Memory**: Max 1GB

#### Gitaly (Git Storage)
- **Purpose**: Git repository storage and operations
- **Socket**: Unix socket (internal)
- **Storage**: `/var/opt/gitlab/git-data/repositories`

#### GitLab Workhorse
- **Purpose**: Handles file uploads/downloads
- **Integration**: Reverse proxy to Puma
- **Features**: Git HTTP operations, file buffering

#### GitLab Shell
- **Purpose**: Git over SSH operations
- **Port**: 22 (mapped to host 2222)
- **Auth**: SSH keys stored in database

### Integrated Services

#### PostgreSQL (Internal)
- **Version**: 14.x (bundled)
- **Database**: gitlabhq_production
- **Location**: `/var/opt/gitlab/postgresql/data`
- **Backup**: Daily via gitlab-backup

#### Redis (Internal)
- **Version**: 7.x (bundled)
- **Purpose**: Cache, sessions, queues
- **Socket**: Unix socket
- **Persistence**: RDB snapshots

#### NGINX (Internal)
- **Purpose**: Internal reverse proxy
- **Port**: 80
- **Routes**: Puma, Workhorse, Registry

#### Container Registry
- **URL**: https://registry.gitlab.ai-servicers.com
- **Port**: 5050 (internal)
- **Storage**: `/var/opt/gitlab/gitlab-rails/shared/registry`
- **Auth**: GitLab JWT tokens

### External Integrations

#### Keycloak SSO
- **Protocol**: OpenID Connect
- **Client ID**: gitlab
- **Endpoints**:
  - Authorization: https://keycloak.ai-servicers.com/... (external)
  - Token: http://keycloak:8080/... (internal)
  - UserInfo: http://keycloak:8080/... (internal)

#### Traefik Reverse Proxy
- **Network**: traefik-net
- **TLS**: Let's Encrypt certificates
- **Routes**:
  - gitlab.ai-servicers.com → Port 80
  - registry.gitlab.ai-servicers.com → Port 5050

#### SendGrid Email Relay
- **Purpose**: Outbound email delivery
- **Port**: 587 (SMTP)
- **Auth**: API key in environment

## Data Flow

### Git Operations
```
1. Git Push (SSH)
   User → Port 2222 → GitLab Shell → Gitaly → Repository

2. Git Clone (HTTPS)
   User → Traefik → NGINX → Workhorse → Gitaly → Repository

3. Web Interface
   User → Traefik → NGINX → Puma → Rails Application
```

### CI/CD Pipeline
```
1. Commit triggers pipeline
2. Sidekiq queues job
3. Runner polls for jobs
4. Runner executes in Docker
5. Artifacts stored in object storage
6. Results displayed in UI
```

### Authentication Flow
```
1. User visits GitLab
2. Redirect to Keycloak
3. User authenticates
4. Keycloak returns token
5. GitLab validates token
6. Session created in Redis
7. User authorized
```

## Storage Architecture

### Directory Structure
```
/home/administrator/projects/
├── gitlab/                      # Scripts and configs
├── data/gitlab/
│   ├── config/                 # GitLab configuration
│   │   └── gitlab.rb          # Main config file
│   ├── data/                  # Application data
│   │   ├── git-data/         # Git repositories
│   │   ├── gitlab-rails/     # Rails app data
│   │   ├── gitlab-shell/     # SSH keys
│   │   └── postgresql/       # Database
│   └── logs/                 # All service logs
└── backups/gitlab/           # Backup storage
```

### Persistent Volumes
- **Config**: `/etc/gitlab` → `data/gitlab/config`
- **Data**: `/var/opt/gitlab` → `data/gitlab/data`
- **Logs**: `/var/log/gitlab` → `data/gitlab/logs`
- **Backups**: `/var/opt/gitlab/backups` → `backups/gitlab`

## Network Architecture

### Docker Networks
- **traefik-net**: External access via Traefik
- **gitlab-net**: Internal GitLab services

### Port Mappings
| Service | External | Internal | Protocol |
|---------|----------|----------|----------|
| Web UI | 443 | 80 | HTTPS→HTTP |
| SSH | 2222 | 22 | TCP |
| Registry | 443 | 5050 | HTTPS→HTTP |

### Special Network Configuration
```bash
--add-host keycloak.ai-servicers.com:172.22.0.3
```
Required for GitLab to resolve Keycloak internally for backend OAuth calls.

## Security Architecture

### Authentication Methods
1. **Local**: Username/password (root account)
2. **SSO**: Keycloak OpenID Connect
3. **Git**: SSH keys or HTTPS tokens
4. **API**: Personal access tokens

### Authorization
- **Groups**: Organizational units
- **Projects**: Repository permissions
- **Roles**: Guest, Reporter, Developer, Maintainer, Owner
- **Protected branches**: Restrict push/merge

### Secrets Management
- **Location**: `$HOME/projects/secrets/gitlab.env`
- **Contains**:
  - Root password
  - OAuth client secret
  - SMTP credentials
  - Database passwords (internal)

## Performance Configuration

### Resource Limits
```yaml
Memory: 4GB
CPUs: 4 cores
Swap: Disabled
```

### Tuning Parameters
```ruby
postgresql['shared_buffers'] = "256MB"
postgresql['max_worker_processes'] = 4
sidekiq['max_concurrency'] = 15
puma['worker_processes'] = 2
puma['per_worker_max_memory_mb'] = 1024
```

### Scaling Considerations
- Vertical: Increase memory/CPU limits
- Horizontal: Add GitLab Runners for CI/CD
- Storage: Expand volume for repositories
- Cache: Use external Redis for better performance

## High Availability (Future)

### Current Limitations
- Single container deployment
- No automatic failover
- Downtime during upgrades

### HA Architecture Path
1. Separate PostgreSQL cluster
2. External Redis cluster
3. Multiple GitLab application nodes
4. Shared NFS/Object storage
5. Load balancer for distribution

## Monitoring Points

### Health Checks
- `/-/health` - Overall health
- `/-/readiness` - Ready for traffic
- `/-/liveness` - Process alive

### Metrics
- Prometheus endpoint: `/-/metrics`
- Sidekiq queue depth
- Database connection pool
- Redis memory usage
- Repository storage usage

### Log Streams
- `production.log` - Rails application
- `sidekiq.log` - Background jobs
- `gitaly.log` - Git operations
- `nginx/access.log` - HTTP requests

## Backup & Recovery

### Backup Components
1. **Application data**: Repositories, uploads, artifacts
2. **Database**: PostgreSQL dump
3. **Configuration**: gitlab.rb, secrets
4. **Container registry**: Image layers

### Recovery Time Objectives
- **RPO**: 24 hours (daily backups)
- **RTO**: 2-4 hours (restore from backup)

---
*Architecture Version: 1.0*
*Last Updated: 2025-08-27*