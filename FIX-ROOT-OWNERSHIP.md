# GitLab Root Ownership Issue & Solutions

## The Problem
GitLab Docker container runs as root (UID 0) internally and creates files owned by root in `/home/administrator/`. This is a **security vulnerability** - user directories should never contain root-owned files.

## Why This Happens
1. GitLab's official Docker image is designed to run as root
2. Many internal services (PostgreSQL, Redis, Nginx, etc.) expect root privileges
3. GitLab modifies and creates files during runtime (SSH keys, secrets, logs)

## Solutions (From Best to Worst)

### Solution 1: Docker User Namespace Remapping (BEST)
Configure Docker daemon to remap root in containers to administrator user.

**Setup:**
```bash
# Edit /etc/docker/daemon.json
{
  "userns-remap": "administrator"
}

# Create subuid and subgid mappings
echo "administrator:2000:1" | sudo tee -a /etc/subuid
echo "administrator:2000:1" | sudo tee -a /etc/subgid

# Restart Docker
sudo systemctl restart docker
```

**Pros:**
- Container root (UID 0) maps to administrator (UID 2000) on host
- All files created will be owned by administrator
- No changes to GitLab needed

**Cons:**
- Affects ALL Docker containers on the system
- Requires Docker daemon restart
- May break other containers expecting real root

### Solution 2: Rootless Podman (RECOMMENDED)
Use Podman instead of Docker to run containers as non-root.

```bash
# Install podman
sudo apt install podman

# Run GitLab with podman as administrator user
podman run -d \
  --name gitlab \
  --hostname gitlab.ai-servicers.com \
  -p 2222:22 \
  -v /home/administrator/data/gitlab/config:/etc/gitlab \
  -v /home/administrator/data/gitlab/logs:/var/log/gitlab \
  -v /home/administrator/data/gitlab/data:/var/opt/gitlab \
  gitlab/gitlab-ce:latest
```

**Pros:**
- Runs entirely as administrator user
- No root privileges needed
- More secure than Docker

**Cons:**
- Requires switching from Docker to Podman
- May have compatibility issues

### Solution 3: Custom GitLab Image with User Switching
Create a custom Dockerfile that switches to administrator user:

```dockerfile
FROM gitlab/gitlab-ce:latest

# Create administrator user inside container with same UID/GID
RUN groupadd -g 2000 administrators && \
    useradd -u 2000 -g 2000 -m administrator

# Attempt to change ownership (will likely fail)
USER administrator
```

**Pros:**
- Keeps using Docker
- Explicit user control

**Cons:**
- GitLab WILL break - it requires root for many operations
- Not practical without extensive modifications

### Solution 4: Volume Permission Fixes with Init Container
Use an init container to fix permissions before GitLab starts:

```bash
# Run permission fixer before GitLab
docker run --rm \
  -v /home/administrator/data/gitlab:/fix \
  alpine:latest \
  sh -c "chown -R 2000:2000 /fix"

# Then start GitLab normally
./deploy.sh
```

**Pros:**
- Simple workaround
- Doesn't modify GitLab

**Cons:**
- Permissions revert on each GitLab restart
- Not a real solution

### Solution 5: Bind Mount with UID/GID Options
Mount volumes with specific ownership:

```bash
docker run -d \
  --name gitlab \
  -v /home/administrator/data/gitlab/config:/etc/gitlab:Z \
  --mount type=bind,source=/home/administrator/data/gitlab/data,target=/var/opt/gitlab,bind-propagation=Z \
  gitlab/gitlab-ce:latest
```

**Cons:**
- Doesn't actually prevent root ownership
- Just a mounting strategy

## Current Workaround
Since GitLab requires root internally, the only practical workaround is:

1. **Accept the security risk** (not recommended)
2. **Regularly fix permissions** with:
   ```bash
   sudo chown -R administrator:administrators /home/administrator/data/gitlab
   sudo chown -R administrator:administrators /home/administrator/projects/gitlab
   ```
3. **Move GitLab data outside home directory** to `/opt/gitlab` or `/srv/gitlab`

## Recommendation
**For production use:**
1. Move GitLab data to `/opt/gitlab/` (owned by root is acceptable there)
2. Or use Podman in rootless mode
3. Or set up Docker user namespace remapping

**The current setup with root-owned files in `/home/administrator` is a security issue and should be fixed.**

## Alternative: Use External GitLab
Consider using:
- GitLab.com (SaaS)
- Gitea (lightweight, runs as non-root)
- Forgejo (Gitea fork, better non-root support)
- Gogs (simple, runs as non-root)

These alternatives don't have the root ownership problem.