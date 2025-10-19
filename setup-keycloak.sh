#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GitLab Keycloak SSO Setup ===${NC}"
echo ""

KEYCLOAK_URL="https://keycloak.ai-servicers.com"
REALM="master"

# Prompt for admin password
echo -e "${YELLOW}Enter Keycloak admin password:${NC}"
read -s ADMIN_PASSWORD
echo ""

echo -e "${YELLOW}Getting admin access token...${NC}"

# Get access token
TOKEN_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" \
  -d "client_id=admin-cli")

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}Failed to get access token. Check admin password.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Authenticated with Keycloak${NC}"
echo ""

# Create GitLab client
echo -e "${YELLOW}Creating GitLab client in Keycloak...${NC}"

CLIENT_CONFIG='{
    "clientId": "gitlab",
    "name": "GitLab CE",
    "enabled": true,
    "protocol": "openid-connect",
    "publicClient": false,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": false,
    "authorizationServicesEnabled": false,
    "redirectUris": [
        "https://gitlab.ai-servicers.com/*",
        "https://gitlab.ai-servicers.com/users/auth/openid_connect/callback"
    ],
    "webOrigins": ["https://gitlab.ai-servicers.com"],
    "attributes": {
        "saml.force.post.binding": "false",
        "saml.multivalued.roles": "false",
        "oauth2.device.authorization.grant.enabled": "false",
        "backchannel.logout.revoke.offline.tokens": "false",
        "saml.server.signature.keyinfo.ext": "false",
        "use.refresh.tokens": "true",
        "oidc.ciba.grant.enabled": "false",
        "client_credentials.use_refresh_token": "false",
        "require.pushed.authorization.requests": "false",
        "saml.client.signature": "false",
        "id.token.as.detached.signature": "false",
        "saml.assertion.signature": "false",
        "saml.encrypt": "false",
        "saml.server.signature": "false",
        "exclude.session.state.from.auth.response": "false",
        "saml.artifact.binding": "false",
        "saml_force_name_id_format": "false",
        "acr.loa.map": "{}",
        "tls.client.certificate.bound.access.tokens": "false",
        "saml.authnstatement": "false",
        "display.on.consent.screen": "false",
        "token.response.type.bearer.lower-case": "false",
        "saml.onetimeuse.condition": "false"
    },
    "defaultClientScopes": ["openid", "profile", "email", "roles", "groups"],
    "optionalClientScopes": ["address", "phone"]
}'

# Create client
RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$CLIENT_CONFIG")

# Get client ID to fetch secret
CLIENT_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=gitlab" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)

if [ -z "$CLIENT_ID" ]; then
    echo -e "${RED}Failed to create client${NC}"
    exit 1
fi

# Get client secret
CLIENT_SECRET=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_ID/client-secret" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')

echo -e "${GREEN}✓ GitLab client created successfully${NC}"
echo ""
echo -e "${BLUE}Client Configuration:${NC}"
echo "Client ID: gitlab"
echo "Client Secret: $CLIENT_SECRET"
echo ""

# Update secrets file with the client secret
echo -e "${YELLOW}Updating secrets file with client secret...${NC}"
SECRETS_FILE="$HOME/projects/secrets/gitlab.env"
sed -i "s/GITLAB_OIDC_CLIENT_SECRET=.*/GITLAB_OIDC_CLIENT_SECRET=$CLIENT_SECRET/" "$SECRETS_FILE"

echo -e "${GREEN}✓ Configuration saved${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart GitLab to apply SSO configuration:"
echo "   docker-compose restart gitlab"
echo ""
echo "2. Wait for GitLab to restart (2-3 minutes)"
echo ""
echo "3. Test SSO login at https://gitlab.ai-servicers.com"
echo ""
echo -e "${BLUE}Note:${NC} Users will be auto-created on first SSO login"