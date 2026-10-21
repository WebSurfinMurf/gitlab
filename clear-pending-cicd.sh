#!/bin/bash
# Clear all pending CI/CD jobs across all GitLab projects and reset runners
# Usage: ./clear-pending-cicd.sh [--dry-run]

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}=== DRY RUN MODE - No changes will be made ===${NC}"
    echo ""
fi

echo -e "${GREEN}=== GitLab CI/CD Cleanup Script ===${NC}"
echo ""

# Check if GitLab container is running
if ! docker ps | grep -q "^.*gitlab[^-]"; then
    echo -e "${RED}Error: GitLab container is not running${NC}"
    exit 1
fi

# Step 1: Show current state
echo -e "${BLUE}Step 1: Analyzing current CI/CD state...${NC}"
echo ""

# Get pipeline counts
PENDING_COUNT=$(docker exec gitlab gitlab-rails runner "puts Ci::Pipeline.where(status: ['pending', 'running', 'created']).count" 2>/dev/null)
echo -e "  Found ${YELLOW}${PENDING_COUNT}${NC} pending/running/created pipelines"

# List pipelines with details
echo ""
echo -e "${BLUE}Pending/Running Pipelines:${NC}"
docker exec gitlab gitlab-rails runner "
Ci::Pipeline.where(status: ['pending', 'running', 'created']).order(:created_at).each do |p|
  puts \"  Pipeline ##{p.id} | #{p.project.path_with_namespace.ljust(40)} | #{p.status.ljust(10)} | #{p.created_at.strftime('%Y-%m-%d %H:%M')}\"
end
" 2>/dev/null || echo "  None found"

# Get job counts
JOB_COUNT=$(docker exec gitlab gitlab-rails runner "puts Ci::Build.where(status: ['pending', 'running', 'created']).count" 2>/dev/null)
echo ""
echo -e "  Found ${YELLOW}${JOB_COUNT}${NC} pending/running/created jobs"

echo ""
echo -e "${BLUE}Pending/Running Jobs:${NC}"
docker exec gitlab gitlab-rails runner "
Ci::Build.where(status: ['pending', 'running', 'created']).order(:created_at).each do |b|
  puts \"  Job ##{b.id} | #{b.name.ljust(25)} | #{b.status.ljust(10)} | Pipeline ##{b.pipeline_id}\"
end
" 2>/dev/null || echo "  None found"

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo -e "${YELLOW}DRY RUN: Would cancel ${PENDING_COUNT} pipelines and ${JOB_COUNT} jobs${NC}"
    echo -e "${YELLOW}DRY RUN: Would reset all runners${NC}"
    exit 0
fi

if [[ "$PENDING_COUNT" == "0" && "$JOB_COUNT" == "0" ]]; then
    echo ""
    echo -e "${GREEN}No pending CI/CD jobs to clear!${NC}"
else
    # Step 2: Cancel all pending/running pipelines
    echo ""
    echo -e "${BLUE}Step 2: Canceling all pending/running pipelines...${NC}"

    docker exec gitlab gitlab-rails runner "
canceled = 0
failed = 0
Ci::Pipeline.where(status: ['pending', 'running', 'created']).find_each do |pipeline|
  begin
    pipeline.cancel_running(auto_canceled_by_pipeline_id: nil)
    canceled += 1
    puts \"  ✓ Canceled pipeline ##{pipeline.id} (#{pipeline.project.path_with_namespace})\"
  rescue => e
    failed += 1
    puts \"  ✗ Failed to cancel pipeline ##{pipeline.id}: #{e.message}\"
  end
end
puts \"\"
puts \"Canceled: #{canceled}, Failed: #{failed}\"
" 2>/dev/null

    # Step 3: Force-cancel any remaining stuck jobs
    echo ""
    echo -e "${BLUE}Step 3: Force-canceling any remaining stuck jobs...${NC}"

    docker exec gitlab gitlab-rails runner "
canceled = 0
Ci::Build.where(status: ['pending', 'running', 'created']).find_each do |job|
  begin
    job.cancel!
    canceled += 1
    puts \"  ✓ Canceled job ##{job.id} (#{job.name})\"
  rescue => e
    # Try direct status update as fallback
    begin
      job.update_columns(status: 'canceled')
      canceled += 1
      puts \"  ✓ Force-canceled job ##{job.id} (#{job.name})\"
    rescue => e2
      puts \"  ✗ Failed to cancel job ##{job.id}: #{e2.message}\"
    end
  end
end
puts \"\"
puts \"Total jobs canceled: #{canceled}\"
" 2>/dev/null
fi

# Step 4: Reset all GitLab runners
echo ""
echo -e "${BLUE}Step 4: Resetting GitLab runners...${NC}"

RUNNERS=("gitlab-runner-admin" "gitlab-runner-dev" "gitlab-runner-docker-admin" "gitlab-runner-docker-dev")

for runner in "${RUNNERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${runner}$"; then
        echo -e "  Restarting ${YELLOW}${runner}${NC}..."
        docker restart "$runner" > /dev/null 2>&1
        echo -e "  ${GREEN}✓${NC} ${runner} restarted"
    else
        echo -e "  ${YELLOW}⚠${NC} ${runner} not running (skipped)"
    fi
done

# Step 5: Verify cleanup
echo ""
echo -e "${BLUE}Step 5: Verifying cleanup...${NC}"
sleep 2

REMAINING_PIPELINES=$(docker exec gitlab gitlab-rails runner "puts Ci::Pipeline.where(status: ['pending', 'running', 'created']).count" 2>/dev/null)
REMAINING_JOBS=$(docker exec gitlab gitlab-rails runner "puts Ci::Build.where(status: ['pending', 'running', 'created']).count" 2>/dev/null)

echo ""
if [[ "$REMAINING_PIPELINES" == "0" && "$REMAINING_JOBS" == "0" ]]; then
    echo -e "${GREEN}=== Cleanup Complete ===${NC}"
    echo -e "  ${GREEN}✓${NC} All pending pipelines cleared"
    echo -e "  ${GREEN}✓${NC} All pending jobs cleared"
    echo -e "  ${GREEN}✓${NC} All runners restarted"
else
    echo -e "${YELLOW}=== Cleanup Partially Complete ===${NC}"
    echo -e "  Remaining pipelines: ${REMAINING_PIPELINES}"
    echo -e "  Remaining jobs: ${REMAINING_JOBS}"
    echo ""
    echo -e "${YELLOW}Some items may still be processing. Run again if needed.${NC}"
fi

echo ""
echo -e "${BLUE}Runner status:${NC}"
for runner in "${RUNNERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${runner}$"; then
        STATUS=$(docker exec "$runner" gitlab-runner status 2>&1 | head -1 || echo "unknown")
        echo -e "  ${runner}: ${GREEN}running${NC}"
    fi
done
