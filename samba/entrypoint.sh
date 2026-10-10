#!/bin/bash
set -euo pipefail

# --- Variables requises ------------------------------------------------
: "${LDAP_URI:?LDAP_URI est requis, ex: ldap://openldap:389}"
: "${LDAP_BASE_DN:?LDAP_BASE_DN est requis, ex: dc=home,dc=lan}"
: "${LDAP_BIND_DN:?LDAP_BIND_DN est requis, ex: cn=admin,dc=home,dc=lan}"
: "${LDAP_BIND_PASSWORD:?LDAP_BIND_PASSWORD est requis}"

# --- Variables avec valeur par défaut -----------------------------------
export LDAP_PEOPLE_OU="${LDAP_PEOPLE_OU:-ou=people}"
export LDAP_GROUP_OU="${LDAP_GROUP_OU:-ou=groups}"
export SAMBA_WORKGROUP="${SAMBA_WORKGROUP:-WORKGROUP}"
export SAMBA_NETBIOS_NAME="${SAMBA_NETBIOS_NAME:-UNRAID-SAMBA}"
export SAMBA_SERVER_STRING="${SAMBA_SERVER_STRING:-Unraid LDAP Samba}"
export LDAP_URI LDAP_BASE_DN LDAP_BIND_DN LDAP_BIND_PASSWORD

echo "[entrypoint] Génération de /etc/samba/smb.conf et /etc/nslcd.conf..."
envsubst < /templates/smb.conf.tmpl > /etc/samba/smb.conf
envsubst < /templates/nslcd.conf.tmpl > /etc/nslcd.conf
chmod 600 /etc/nslcd.conf
chown nslcd:nslcd /etc/nslcd.conf || true

# Fichier de shares : créé vide au premier démarrage si absent, pour que
# l'utilisateur puisse l'éditer depuis Unraid (chemin monté en volume)
# sans faire planter l'include de smb.conf.
if [ ! -f /etc/samba/smb-shares.conf ]; then
  echo "[entrypoint] Aucun /etc/samba/smb-shares.conf trouvé, création d'un fichier vide."
  echo "# Ajoutez vos partages ici, voir smb-shares.conf.example" > /etc/samba/smb-shares.conf
fi

# --- Attente de la disponibilité de LDAP --------------------------------
echo "[entrypoint] Attente de LDAP (${LDAP_URI})..."
until ldapsearch -x -H "$LDAP_URI" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" -b "$LDAP_BASE_DN" -s base >/dev/null 2>&1; do
  sleep 2
done
echo "[entrypoint] LDAP disponible."

# --- Bootstrap de l'entrée sambaDomain (une seule fois) -----------------
if ! ldapsearch -x -H "$LDAP_URI" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" \
      -b "$LDAP_BASE_DN" "(objectClass=sambaDomain)" sambaSID 2>/dev/null | grep -q "^sambaSID:"; then

  echo "[entrypoint] Aucun domaine Samba dans LDAP : génération d'un SID et création de l'entrée sambaDomain."
  R1=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
  R2=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
  R3=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
  SID="S-1-5-21-${R1}-${R2}-${R3}"

  cat > /tmp/sambadomain.ldif <<EOF
dn: sambaDomainName=${SAMBA_WORKGROUP},${LDAP_BASE_DN}
objectClass: sambaDomain
objectClass: top
sambaDomainName: ${SAMBA_WORKGROUP}
sambaSID: ${SID}
sambaAlgorithmicRidBase: 1000
EOF

  ldapadd -x -H "$LDAP_URI" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" -f /tmp/sambadomain.ldif
  rm -f /tmp/sambadomain.ldif
  echo "[entrypoint] Domaine Samba créé avec SID ${SID}."
else
  echo "[entrypoint] Domaine Samba déjà présent dans LDAP, rien à faire."
fi

# --- Stockage du mot de passe de bind LDAP pour Samba (secrets.tdb) -----
# Samba n'accepte jamais de mot de passe en clair dans smb.conf : il faut
# le pousser dans secrets.tdb via smbpasswd -w. Idempotent, sans risque à
# rejouer à chaque démarrage.
echo "[entrypoint] Enregistrement du mot de passe de bind LDAP dans secrets.tdb..."
( echo "$LDAP_BIND_PASSWORD" ) | smbpasswd -w "$LDAP_BIND_PASSWORD" >/dev/null

# --- Alignement du SID local de Samba sur celui du domaine stocké dans LDAP ---
# Samba conserve son propre SID dans secrets.tdb. S'il diffère de celui de l'entrée
# sambaDomain (utilisé pour fabriquer le SID de chaque compte), l'authentification
# échoue avec NT_STATUS_INVALID_SID ("sid ... does not belong to our domain").
# Opération idempotente, rejouée à chaque démarrage.
DOMAIN_SID="$(ldapsearch -x -LLL -H "$LDAP_URI" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" \
  -b "$LDAP_BASE_DN" "(&(objectClass=sambaDomain)(sambaDomainName=${SAMBA_WORKGROUP}))" sambaSID \
  | sed -n 's/^sambaSID: //p')"
DOMAIN_SID="${DOMAIN_SID%%$'\n'*}"
if [ -z "$DOMAIN_SID" ]; then
  echo "[entrypoint] ERREUR : SID du domaine ${SAMBA_WORKGROUP} introuvable dans LDAP." >&2
  exit 1
fi
echo "[entrypoint] Alignement du SID local de Samba sur ${DOMAIN_SID}..."
net setlocalsid "$DOMAIN_SID"
net setdomainsid "$DOMAIN_SID" || echo "[entrypoint] AVERTISSEMENT : net setdomainsid a échoué (non bloquant)."

# --- Démarrage des services ---------------------------------------------
echo "[entrypoint] Démarrage de nslcd..."
nslcd

echo "[entrypoint] Démarrage de wsdd (découverte réseau Windows 10/11)..."
wsdd -i "$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')" &

echo "[entrypoint] Démarrage de nmbd..."
nmbd -F --no-process-group &

echo "[entrypoint] Démarrage de smbd (premier plan)..."
exec smbd -F --no-process-group
