---
source: gemini
reviewed: 2026-08-16
context: dev-runner-boundary.md
---

### 1. Assessment of the Draft Position
Your draft position is pragmatic, highly aware of the current host environment, and correctly identifies the core truth: **the requested boundary cannot be enforced if the human developer retains `docker` and `sudo` groups on the same host.** You correctly identify that Runner 3, via the `SSH-as-websurfinmurf` pattern, is already host-root-equivalent, making any internal CI gymnastics nominal containment at best. Your push to migrate `ib-gateway` to Runner 10 to finally retire Runner 7 is spot-on and prioritizes the highest-value structural risk.

However, your dismissal of the broker pattern (Option B) relies on a fundamentally flawed assumption about how brokers are designed, and your reliance on `ref_protected` misses a critical failure mode regarding GitLab group permissions.

### 2. What I'd Do Differently
*   **Acknowledge the true reason Option B is a ritual:** I would reject the broker, but **not** because brokers can't secure compose files. I would reject it because implementing a strict CI boundary for a user who can SSH into the host and run `docker run --privileged` manually is security theater.
*   **Address the `ref_protected` illusion:** I would explicitly state that `ref_protected` is not a boundary against the developer, but only against *non-maintainer* compromise. If `websurfinmurf` is compromised, CI is compromised.
*   **Secure the SSH pattern:** I would mandate tightening the SSH key on Runner 3, as shipping an unrestricted SSH key inside a CI runner introduces persistent host-compromise risks.

### 3. Specific Suggestions and Rationale

**Attack on the "Broker is a ritual" argument (Point 2):**
Your draft argues a broker is a ritual because it *must* faithfully execute the developer's `docker-compose.yml` and `deploy.sh`. **This is a failure of imagination regarding deployment patterns.**

A small, ~15-line broker genuinely and absolutely constrains developer-controlled content by severing the configuration from the artifact.
```bash
#!/bin/bash
# /usr/local/bin/deploy-broker
PROJECT=$1
TAG=$2

# 1. Strict input validation
if [[ ! "$PROJECT" =~ ^[a-zA-Z0-9_-]+$ ]] || [[ ! "$TAG" =~ ^[a-zA-Z0-9_.-]+$ ]]; then exit 1; fi

# 2. Admin-owned deployment configuration directory
ADMIN_COMPOSE_DIR="/etc/deployments/${PROJECT}"
if [[ ! -d "$ADMIN_COMPOSE_DIR" ]]; then exit 1; fi

# 3. Execute against the admin's config, NOT the developer's repo
cd "$ADMIN_COMPOSE_DIR" || exit 1
export IMAGE_TAG="$TAG"
docker compose pull && docker compose up -d
```
With this design, the developer *only* controls the application code and the image tag pushed to the registry. The administrator controls the `docker-compose.yml` (located in `/etc/deployments/`), meaning the admin hardcodes the volumes, network, and privileges. The developer cannot inject `volumes: ["/:/host"]` because their compose file is completely ignored.

Therefore, a broker *can* be a perfect boundary. However, you should still advise against it, because building an ironclad broker for CI is pointless when the developer human can just SSH into the box and run `sudo`.

**Other Suggestions:**
*   **Draft Point 1 (SSH Recommendation):** Keep this recommendation, but add a requirement to lock down the SSH key. The `authorized_keys` entry for Runner 3's key in `websurfinmurf`'s `~/.ssh/authorized_keys` must use `command="..."` restrictions (e.g., restricted to specific deploy scripts) rather than allowing full interactive shell allocation.
*   **Draft Point 4 (Honest Answer):** Keep this exactly as is. It is mathematically correct. A boundary against a `sudo`/`docker` user on a single host does not exist.

### 4. Risks or Gotchas Missed by Both Parties

*   **The "Owner/Maintainer" Bypass on `ref_protected`:** Both the note and the draft lean heavily on `ref_protected` as a gate. However, if `websurfinmurf` is the GitLab Group Owner or Project Maintainer, they can trivially modify branch protection rules or push malicious code directly to the protected branch. `ref_protected` only stops junior developers or external PRs; it provides **zero boundary** against the repository owner.
*   **Persistent Host Compromise via Runner 3's SSH Key:** The draft notes Runner 3 ships with `/home/gitlab-runner/.ssh/id_ed25519` allowing login as `websurfinmurf`. If Runner 3 is compromised (e.g., via a malicious dependency executed during a CI job on a protected branch), the attacker can exfiltrate this private SSH key. Because `websurfinmurf` has `sudo` and `docker` groups, stealing this single CI SSH key instantly grants the attacker full, persistent host root. This is a massive lateral movement vector.
*   **The Docker Daemon is the true root of trust:** The requester states: *"I don't care if each developer can reach each other's stuff. I DO care developers cannot modify administrators' stuff."* Because all containers share the same Docker daemon on this host, any container (even if deployed by an honest broker) that is granted `docker.sock` access or `--privileged` by the admin can be hijacked by the developer modifying the underlying image. The only way to protect the admin's containers from the developer's containers is total daemon isolation (e.g., separate hosts or true hardware virtualization).
