# GitLab Intermittent 502 Errors - Troubleshooting Guide

## Problem Description
GitLab works initially after container start, but after ~1 minute of usage, returns HTTP 502 errors. This is almost always caused by file permission issues preventing services from starting properly.

## PRIMARY SOLUTION (95% of cases)

### **File Permission Issues** ⚠️ CRITICAL
The most common cause is corrupted file ownership preventing GitLab services from starting:

```bash
# THIS FIXES MOST 502 ERRORS:
docker exec gitlab update-permissions
docker restart gitlab

# Wait for services to start
sleep 60
docker exec gitlab gitlab-ctl status
```

**Why this happens:**
- GitLab Docker uses internal users with specific UIDs
- Manual permission changes break service startup
- Even `chmod 777` won't fix it - Ruby checks ownership too

**GitLab Internal Users:**
- `git` (UID 998) - Rails, Puma, Workhorse
- `gitlab-psql` (UID 996) - PostgreSQL
- `gitlab-redis` (UID 997) - Redis  
- `gitlab-www` (UID 999) - Nginx

## Secondary Root Causes (if update-permissions doesn't fix it)

### 1. **Puma Worker Crashes**
- Puma workers crash/become unresponsive while container stays partially functional
- CPU usage spikes to 99% and memory increases monotonically
- Works for 3-4 seconds during restart, then fails again

### 2. **Workhorse Connection Timeouts**
- Workhorse can't connect to Puma on 127.0.0.1:8080
- Default 30-second timeout before returning 502
- Socket connection shows as "connection refused"

### 3. **Resource Constraints**
- Insufficient memory allocation for Puma workers
- CPU limits too restrictive
- Shared buffers too small in PostgreSQL

### 4. **PID 1 Signal Handling**
- Container doesn't properly handle TERM signals for graceful shutdown
- Zombie processes accumulate

## Immediate Fixes to Try

### 1. **Check Permissions First**
```bash
# Always try this first before changing resources
docker exec gitlab update-permissions
docker restart gitlab
```

### 2. **Increase Resource Limits (if needed)**
Edit `/home/administrator/projects/gitlab/deploy.sh`:
```bash
# Default settings work fine once permissions are fixed:
--memory="4g" \  
--cpus="2" \
```

### 2. **Adjust Puma Configuration**
Add to `gitlab.rb`:
```ruby
# Reduce Puma workers to prevent memory exhaustion
puma['worker_processes'] = 2  # Default is 4
puma['per_worker_max_memory_mb'] = 1024  # Force restart if worker uses >1GB
puma['worker_timeout'] = 60  # Increase from default 30

# Enable Puma killer to restart workers
puma['enable'] = true
puma['ha'] = false  # Disable high availability mode
```

### 3. **Workhorse Timeout Adjustments**
```ruby
# In gitlab.rb
gitlab_workhorse['shutdown_timeout'] = "60s"
gitlab_workhorse['api_queue_duration'] = "60s"
gitlab_workhorse['api_limit'] = 100
```

### 4. **PostgreSQL Tuning**
```ruby
# Already in gitlab.rb but can be increased
postgresql['shared_buffers'] = "512MB"  # Increase from 256MB
postgresql['max_connections'] = 200
postgresql['checkpoint_segments'] = 10
postgresql['checkpoint_completion_target'] = 0.9
```

## Enable Debug Logging

### 1. **Create Debug Configuration**
Add to `/home/administrator/data/gitlab/config/gitlab.rb`:
```ruby
# Enable debug logging
gitlab_rails['env'] = {
  'GITLAB_LOG_LEVEL' => 'debug'
}

# Verbose logging for all components
logging['svlogd_size'] = 200 * 1024 * 1024  # 200MB
logging['svlogd_num'] = 30  # Keep 30 rotated log files
logging['logrotate_frequency'] = "daily"
logging['logrotate_maxsize'] = "200M"

# Component-specific debug
nginx['error_log_level'] = "debug"
gitlab_workhorse['log_format'] = "json"
registry['debug_addr'] = "localhost:5001"

# Rails logging
gitlab_rails['log_level'] = "debug"
```

### 2. **Monitor Logs in Real-Time**
Create monitoring script `/home/administrator/projects/gitlab/monitor-502.sh`:
```bash
#!/bin/bash
echo "=== GitLab 502 Error Monitor ==="
echo "Watching for connection issues..."

# Terminal 1: Watch Puma logs
docker exec gitlab tail -f /var/log/gitlab/puma/puma_stderr.log &

# Terminal 2: Watch Workhorse logs
docker exec gitlab tail -f /var/log/gitlab/gitlab-workhorse/current &

# Terminal 3: Watch nginx errors
docker exec gitlab tail -f /var/log/gitlab/nginx/gitlab_error.log &

# Monitor memory usage
while true; do
  echo "=== $(date) ==="
  docker exec gitlab ps aux | grep -E "(puma|workhorse)" | grep -v grep
  sleep 5
done
```

### 3. **Debug Commands**
```bash
# Check if Puma is actually listening
docker exec gitlab ss -tlnp | grep 8080

# Test Puma directly
docker exec gitlab curl -I http://127.0.0.1:8080

# Check Workhorse socket
docker exec gitlab ls -la /var/opt/gitlab/gitlab-workhorse/sockets/

# Test Workhorse socket
docker exec gitlab curl --unix-socket /var/opt/gitlab/gitlab-workhorse/sockets/socket http://localhost/

# Check for zombie processes
docker exec gitlab ps aux | grep defunct

# Memory usage by component
docker exec gitlab ps aux --sort=-%mem | head -20
```

## Long-term Solutions

### 1. **Health Check Improvements**
Add to docker run command:
```bash
--health-cmd "curl -f http://localhost/-/readiness || exit 1" \
--health-interval 10s \
--health-timeout 3s \
--health-retries 3 \
--health-start-period 600s \
```

### 2. **Container Restart Policy**
```bash
--restart unless-stopped \
--restart-delay 10s \
```

### 3. **Network Optimizations**
```ruby
# In gitlab.rb
nginx['keepalive_timeout'] = 65
nginx['proxy_connect_timeout'] = 300
nginx['proxy_read_timeout'] = 300
nginx['proxy_send_timeout'] = 300
```

### 4. **Database Connection Pooling**
```ruby
gitlab_rails['db_pool'] = 10  # Match Puma workers
gitlab_rails['db_connect_timeout'] = 5
```

## Diagnostic Script
Create `/home/administrator/projects/gitlab/diagnose-502.sh`:
```bash
#!/bin/bash
set -e

echo "=== GitLab 502 Diagnostic ==="
echo "Date: $(date)"
echo ""

echo "1. Container Status:"
docker ps | grep gitlab

echo -e "\n2. Service Status:"
docker exec gitlab gitlab-ctl status

echo -e "\n3. Memory Usage:"
docker exec gitlab free -h

echo -e "\n4. Puma Process:"
docker exec gitlab ps aux | grep puma | head -5

echo -e "\n5. Recent Errors:"
docker exec gitlab grep -i "error\|fail\|502" /var/log/gitlab/nginx/gitlab_error.log | tail -10

echo -e "\n6. Workhorse Connection Test:"
docker exec gitlab curl -I --unix-socket /var/opt/gitlab/gitlab-workhorse/sockets/socket http://localhost/ 2>&1 | head -5

echo -e "\n7. Puma Direct Test:"
docker exec gitlab curl -I http://127.0.0.1:8080 2>&1 | head -5

echo -e "\n8. Network Connectivity:"
docker exec gitlab ss -tlnp | grep -E "(8080|80)"

echo -e "\n9. Disk Space:"
docker exec gitlab df -h /var/opt/gitlab

echo -e "\n10. Recent Puma Restarts:"
docker exec gitlab grep "puma startup" /var/log/gitlab/puma/puma_stderr.log | tail -5
```

## Emergency Recovery
If GitLab becomes completely unresponsive:
```bash
# Force restart all services
docker exec gitlab gitlab-ctl restart

# If that fails, restart container
docker restart gitlab

# If still failing, recreate with increased resources
docker stop gitlab
docker rm gitlab
# Edit deploy.sh to increase memory/cpu
./deploy.sh
```

## References
- [GitLab Forum: Puma restarting every minute](https://forum.gitlab.com/t/gitlab-502-error-puma-restarting-every-minute/63190)
- [GitLab Blog: Reducing 502 errors with PID 1](https://about.gitlab.com/blog/2022/05/17/how-we-removed-all-502-errors-by-caring-about-pid-1-in-kubernetes/)
- [GitLab Docs: Log system](https://docs.gitlab.com/administration/logs/)

---
*Created: 2025-08-27*
*Issue: GitLab works initially then fails with 502 after ~1 minute*