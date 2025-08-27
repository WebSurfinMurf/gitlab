#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Import Dashy Project to GitLab ===${NC}"
echo ""

# Check if GitLab is ready
echo -e "${YELLOW}Checking GitLab availability...${NC}"
if ! curl -s -o /dev/null -w "%{http_code}" https://gitlab.ai-servicers.com | grep -q "302\|200"; then
    echo -e "${RED}GitLab is not accessible. Please ensure it's running.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ GitLab is accessible${NC}"
echo ""

# Create .gitlab-ci.yml for Dashy
echo -e "${YELLOW}Creating CI/CD pipeline configuration...${NC}"

cat > /home/administrator/projects/dashy/.gitlab-ci.yml << 'EOF'
# GitLab CI/CD Pipeline for Dashy
# Auto-deploys on changes to main branch

stages:
  - validate
  - backup
  - deploy
  - notify

variables:
  DASHY_CONTAINER: "dashy"
  DASHY_PATH: "/home/administrator/projects/dashy"

validate-config:
  stage: validate
  image: node:alpine
  script:
    - apk add --no-cache yamllint
    - yamllint -d relaxed config/conf.yml
    - echo "✅ Configuration is valid"
  only:
    changes:
      - config/conf.yml

backup-current:
  stage: backup
  image: alpine
  script:
    - cp config/conf.yml config/conf.yml.backup.$(date +%Y%m%d_%H%M%S)
    - echo "✅ Backup created"
  artifacts:
    paths:
      - config/*.backup.*
    expire_in: 30 days
  only:
    - main

deploy-dashy:
  stage: deploy
  image: docker:latest
  services:
    - docker:dind
  script:
    - echo "🚀 Deploying Dashy updates..."
    - |
      # Copy new config to server
      docker cp config/conf.yml ${DASHY_CONTAINER}:/app/user-data/conf.yml
      
      # Restart container to reload mount
      docker restart ${DASHY_CONTAINER}
      
      # Wait for container to be healthy
      sleep 10
      
      # Trigger rebuild
      docker exec ${DASHY_CONTAINER} yarn build
      
      echo "✅ Dashy deployed successfully"
  only:
    - main
  when: on_success

rollback-on-failure:
  stage: deploy
  image: docker:latest
  script:
    - echo "⚠️ Deployment failed, rolling back..."
    - |
      # Find latest backup
      LATEST_BACKUP=$(ls -t config/*.backup.* | head -1)
      if [ -f "$LATEST_BACKUP" ]; then
        docker cp $LATEST_BACKUP ${DASHY_CONTAINER}:/app/user-data/conf.yml
        docker restart ${DASHY_CONTAINER}
        docker exec ${DASHY_CONTAINER} yarn build
        echo "✅ Rolled back to $LATEST_BACKUP"
      fi
  only:
    - main
  when: on_failure

notify-success:
  stage: notify
  image: alpine
  script:
    - echo "✅ Deployment completed successfully"
    - echo "View at: https://dashy.ai-servicers.com"
  only:
    - main
  when: on_success

# Manual job to sync with GitHub
mirror-to-github:
  stage: deploy
  image: alpine/git
  script:
    - git remote add github https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/dashy.git || true
    - git push github main --force
    - echo "✅ Mirrored to GitHub"
  when: manual
  only:
    - main
EOF

echo -e "${GREEN}✓ CI/CD pipeline created${NC}"
echo ""

echo -e "${YELLOW}Creating GitLab project README...${NC}"
cat > /home/administrator/projects/dashy/README-GITLAB.md << 'EOF'
# Dashy Dashboard - GitLab Managed

This repository manages the Dashy dashboard configuration for ai-servicers.com.

## 🚀 Auto-Deployment

Changes pushed to the `main` branch automatically:
1. Validate YAML configuration
2. Create backup of current config
3. Deploy to production
4. Rebuild Dashy container
5. Rollback on failure

## 📝 Making Changes

1. Edit `config/conf.yml`
2. Commit and push to `main`
3. Pipeline automatically deploys

## 🔄 GitHub Mirror

This repository is mirrored to GitHub for backup:
- Primary: https://gitlab.ai-servicers.com/infrastructure/dashy
- Mirror: https://github.com/[your-username]/dashy

## 📊 Pipeline Status

[![pipeline status](https://gitlab.ai-servicers.com/infrastructure/dashy/badges/main/pipeline.svg)](https://gitlab.ai-servicers.com/infrastructure/dashy/-/commits/main)

## 🛠️ Manual Deployment

If needed, deploy manually:
```bash
cd /home/administrator/projects/dashy
docker exec dashy yarn build
```

## 📚 Documentation

- [Dashy Docs](https://dashy.to/docs)
- [Organization Guide](./DASHY-ORGANIZATION.md)
- [Services Inventory](./SERVICES-INVENTORY.yml)
EOF

echo -e "${GREEN}✓ README created${NC}"
echo ""

echo -e "${BLUE}=== Next Steps ===${NC}"
echo ""
echo "1. Start GitLab if not running:"
echo "   cd /home/administrator/projects/gitlab && ./deploy.sh"
echo ""
echo "2. Wait for GitLab to be ready (5-10 minutes first run)"
echo ""
echo "3. Login to GitLab:"
echo "   https://gitlab.ai-servicers.com"
echo "   root / [password from .env]"
echo ""
echo "4. Create a new project:"
echo "   - Name: dashy"
echo "   - Namespace: infrastructure (create if needed)"
echo "   - Visibility: Private"
echo ""
echo "5. Push Dashy to GitLab:"
echo "   cd /home/administrator/projects/dashy"
echo "   git init"
echo "   git add ."
echo "   git commit -m 'Initial Dashy configuration'"
echo "   git remote add origin git@gitlab.ai-servicers.com:infrastructure/dashy.git"
echo "   git push -u origin main"
echo ""
echo "6. Setup GitHub mirror:"
echo "   - In GitLab: Settings → Repository → Mirroring repositories"
echo "   - URL: https://github.com/[username]/dashy.git"
echo "   - Password: GitHub Personal Access Token"
echo "   - Mirror direction: Push"
echo ""
echo "7. Configure CI/CD variables:"
echo "   - Settings → CI/CD → Variables"
echo "   - Add GITHUB_TOKEN (your GitHub PAT)"
echo "   - Add GITHUB_USER (your GitHub username)"
echo ""
echo -e "${GREEN}Ready to revolutionize your deployment workflow!${NC}"