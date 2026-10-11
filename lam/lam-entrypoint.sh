#!/bin/bash
# Prépare le volume de configuration LAM puis lance le démarrage officiel.
# Reste en root : Apache ouvre ses logs (/dev/stdout, détenu par root) puis abaisse
# lui-même ses processus de travail en www-data.
set -euo pipefail

CFG=/var/lib/ldap-account-manager/config
DEF=/opt/lam-defaults/config
ETC_CFG=/etc/ldap-account-manager/config.cfg

mkdir -p "$CFG"

# 1) Volume vide : on y recopie les fichiers de référence (sans écraser l'existant).
if [ ! -e "$CFG/unix.sample.conf" ]; then
  echo "[lam-entrypoint] Volume de configuration vide : copie des fichiers par défaut."
  cp -an "$DEF"/. "$CFG"/
fi

# 2) config.cfg : doit être un vrai fichier DANS le volume (sinon les réglages
#    généraux sont perdus à chaque recréation du conteneur). Le fichier attendu
#    par LAM dans /etc devient un lien vers lui.
if [ -L "$CFG/config.cfg" ] || [ ! -e "$CFG/config.cfg" ]; then
  src="$DEF/config.cfg"
  [ -f "$src" ] || src=/etc/ldap-account-manager/config.cfg
  rm -f "$CFG/config.cfg"
  cp -L "$src" "$CFG/config.cfg"
fi
if [ ! -L "$ETC_CFG" ] || [ "$(readlink "$ETC_CFG")" != "$CFG/config.cfg" ]; then
  rm -f "$ETC_CFG"
  ln -s "$CFG/config.cfg" "$ETC_CFG"
fi

# 3) Première initialisation (pas de lam.conf) : préconfiguration LAM à partir des
#    variables d'environnement. Ensuite on la désactive pour ne jamais réécrire la
#    configuration (profils, modules activés dans l'interface...).
if [ ! -s "$CFG/lam.conf" ]; then
  if [ -z "${LAM_PASSWORD:-}" ] && [ -z "${LAM_PASSWORD_FILE:-}" ]; then
    echo "[lam-entrypoint] ERREUR : première initialisation, LAM_PASSWORD est requis." >&2
    exit 1
  fi
  echo "[lam-entrypoint] Première initialisation de la configuration LAM."
  export LAM_SKIP_PRECONFIGURE=false
else
  export LAM_SKIP_PRECONFIGURE=true
fi

chown -R www-data:www-data "$CFG" /etc/ldap-account-manager

exec /usr/local/bin/start.sh
