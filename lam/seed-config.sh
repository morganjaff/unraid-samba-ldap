#!/bin/bash
# Génère la configuration initiale de LAM dans le dossier appdata.
#
# L'image LAM ne sait pas s'initialiser seule quand son dossier de config est un
# volume vide. Procédure recommandée par le mainteneur : démarrer un conteneur
# jetable SANS volume avec la préconfiguration active, puis copier ses fichiers.
# À exécuter une seule fois, avant le premier démarrage du conteneur "lam".
#
# Exemple :
#   LDAP_SERVER=ldap://192.168.1.10:389 LDAP_BASE_DN=dc=home,dc=lan bash seed-config.sh
set -euo pipefail

LDAP_SERVER="${LDAP_SERVER:?LDAP_SERVER requis, ex: ldap://192.168.1.10:389}"
LDAP_BASE_DN="${LDAP_BASE_DN:?LDAP_BASE_DN requis, ex: dc=home,dc=lan}"
LDAP_USER="${LDAP_USER:-cn=admin,${LDAP_BASE_DN}}"
LDAP_USERS_DN="${LDAP_USERS_DN:-ou=people,${LDAP_BASE_DN}}"
LDAP_GROUPS_DN="${LDAP_GROUPS_DN:-ou=groups,${LDAP_BASE_DN}}"
LAM_LANG="${LAM_LANG:-fr_FR.UTF-8}"
LAM_IMAGE="${LAM_IMAGE:-ghcr.io/ldapaccountmanager/lam:stable}"
DEST="${DEST:-/mnt/user/appdata/lam/config}"

if [ -z "${LAM_PASSWORD:-}" ]; then
  read -r -s -p "Mot de passe maître LAM (à définir) : " LAM_PASSWORD
  echo
fi

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  echo "Refus : $DEST n'est pas vide (une configuration existe peut-être déjà)." >&2
  exit 1
fi

docker rm -f lam-seed >/dev/null 2>&1 || true
echo "Démarrage d'un conteneur LAM jetable..."
docker run -d --name lam-seed \
  -e LAM_SKIP_PRECONFIGURE=false \
  -e LAM_PASSWORD="$LAM_PASSWORD" \
  -e LAM_LANG="$LAM_LANG" \
  -e LDAP_SERVER="$LDAP_SERVER" \
  -e LDAP_BASE_DN="$LDAP_BASE_DN" \
  -e LDAP_USER="$LDAP_USER" \
  -e LDAP_USERS_DN="$LDAP_USERS_DN" \
  -e LDAP_GROUPS_DN="$LDAP_GROUPS_DN" \
  "$LAM_IMAGE" >/dev/null

# La préconfiguration s'exécute avant le démarrage d'Apache : on attend donc
# qu'Apache soit prêt pour être sûr que les fichiers sont générés.
for _ in $(seq 1 60); do
  if docker logs lam-seed 2>&1 | grep -q "resuming normal operations"; then break; fi
  sleep 2
done
sleep 2

mkdir -p "$DEST"
docker cp -L lam-seed:/var/lib/ldap-account-manager/config/. "$DEST"/
# config.cfg est un lien symbolique vers /etc/ldap-account-manager/ dans l'image,
# que "docker cp" ne déréférence pas : on le remplace par le vrai fichier pour que
# les réglages généraux de LAM soient eux aussi conservés dans l'appdata.
rm -f "$DEST/config.cfg"
docker cp -L lam-seed:/etc/ldap-account-manager/config.cfg "$DEST/config.cfg"
WWW_UID="$(docker exec lam-seed id -u www-data)"
WWW_GID="$(docker exec lam-seed id -g www-data)"
chown -R "$WWW_UID:$WWW_GID" "$DEST"
docker rm -f lam-seed >/dev/null

echo "Configuration copiée dans $DEST :"
ls -la "$DEST"
for f in config.cfg lam.conf; do
  [ -f "$DEST/$f" ] || echo "ATTENTION : $f est absent, la configuration est incomplète." >&2
done
