#!/bin/bash

# Perform a simple recursive find-and-replace on all variables defined in setup.conf
export SETUP_CONF_PATH=$1 # location of the setup config
export DISTRIBUTION_PATH=./distribution # folder where the distribution's YAML files are to be found

while IFS="=" read PLACEHOLDER VALUE # While loop that will perform simple parsing. On each line MY_VAR=123 will be read into PLACEHOLDER=MY_VAR, VALUE=123
do
  # recursively look for $PLACEHOLDER in all files in the $DISTRIBUTION_PATH and replace it with $VALUE
  echo ${VALUE}
  VALUE=$(echo "${VALUE////$'\/'}") #escape forward slashes (needed for sed to work correctly)
  grep -rli ${PLACEHOLDER} ${DISTRIBUTION_PATH}/* | xargs -i@ sed -i "s/${PLACEHOLDER}/${VALUE}/g" @ #perform recursive replace
done <${SETUP_CONF_PATH} # pass the setup config into the while loop

COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(16)).decode())')
OIDC_CLIENT_ID=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
OIDC_CLIENT_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

kubectl create secret generic -n auth oauth2-proxy --from-literal=client-id=${OIDC_CLIENT_ID} --from-literal=client-secret=${OIDC_CLIENT_SECRET} --from-literal=cookie-secret=${COOKIE_SECRET} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/dex/oauth2-proxy-secret.yaml
kubectl create secret generic -n auth oauth2-proxy --from-literal=client-id=${OIDC_CLIENT_ID} --from-literal=client-secret=${OIDC_CLIENT_SECRET} --from-literal=cookie-secret=${COOKIE_SECRET} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/oauth2-proxy-secret.yaml

DATABASE_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
POSTGRESQL_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
KEYCLOAK_ADMIN_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
KEYCLOAK_MANAGEMENT_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')

kubectl create secret generic -n auth keycloak-secret --from-literal=admin-password=${KEYCLOAK_ADMIN_PASS} --from-literal=database-password=${DATABASE_PASS} --from-literal=management-password=${KEYCLOAK_MANAGEMENT_PASS} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/keycloak-secret.yaml
kubectl create secret generic -n auth keycloak-postgresql --from-literal=postgresql-password=${DATABASE_PASS} --from-literal=postgresql-postgres-password=${POSTGRESQL_PASS} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/postgresql-secret.yaml

EMAIL="admin@argoflow.org"
USERNAME="admin"
FIRSTNAME="admin"
LASTNAME="admin"
ADMIN_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
ADMIN_PASS_DEX=$(python3 -c "from passlib.hash import bcrypt; print(bcrypt.using(rounds=12, ident='2y').hash(\"${ADMIN_PASS}\"))")

yq eval -i ".data.ADMIN = \"${EMAIL}\"" ${DISTRIBUTION_PATH}/kubeflow/notebooks/profile-controller_access-management/patch-admin.yaml

yq eval ".staticClients[0].id = \"${OIDC_CLIENT_ID}\" | .staticClients[0].secret = \"${OIDC_CLIENT_SECRET}\" | .staticPasswords[0].hash = \"${ADMIN_PASS_DEX}\" | .staticPasswords[0].email = \"${EMAIL}\" | .staticPasswords[0].username = \"${USERNAME}\"" ${DISTRIBUTION_PATH}/oidc-auth/overlays/dex/dex-config-template.yaml | kubectl create secret generic -n auth dex-config --dry-run=client --from-file=config.yaml=/dev/stdin -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/dex/dex-config-secret.yaml
yq eval -j -P ".users[0].username = \"${USERNAME}\" | .users[0].email = \"${EMAIL}\" | .users[0].firstName = \"${FIRSTNAME}\" | .users[0].lastName = \"${LASTNAME}\" | .users[0].credentials[0].value = \"${ADMIN_PASS}\" | .clients[0].clientId = \"${OIDC_CLIENT_ID}\" | .clients[0].secret = \"${OIDC_CLIENT_SECRET}\"" ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/kubeflow-realm-template.json | kubectl create secret generic -n auth kubeflow-realm --dry-run=client --from-file=kubeflow-realm.json=/dev/stdin -o json | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/kubeflow-realm-secret.yaml
