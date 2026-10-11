# Image LAM dérivée : s'initialise seule sur un volume de configuration vide
# (remplace l'ancien script lam/seed-config.sh et son conteneur jetable).
FROM ghcr.io/ldapaccountmanager/lam:stable

USER root

# Copie de référence de la configuration livrée dans l'image : le volume monté
# sur /var/lib/ldap-account-manager/config la masque, on la garde ailleurs.
# -L : config.cfg est un lien symbolique vers /etc/ldap-account-manager/.
RUN mkdir -p /opt/lam-defaults \
 && cp -aL /var/lib/ldap-account-manager/config /opt/lam-defaults/config

# start.sh modifie config.cfg avec "sed -i", qui remplace un lien symbolique par un
# fichier ordinaire : la modification n'atteindrait alors pas le volume. Ce sed
# (prioritaire dans le PATH le temps de start.sh) suit les liens symboliques.
RUN mkdir -p /opt/lam-shim \
 && printf '#!/bin/sh\nexec /bin/sed --follow-symlinks "$@"\n' > /opt/lam-shim/sed \
 && chmod 755 /opt/lam-shim/sed

COPY lam-enable-samba.php /usr/local/bin/lam-enable-samba.php
COPY lam-entrypoint.sh /usr/local/bin/lam-entrypoint.sh
RUN chmod 755 /usr/local/bin/lam-entrypoint.sh

# ENTRYPOINT (dumb-init) hérité de l'image de base ; seul le CMD change.
# Le script reste en root : Apache abaisse lui-même ses workers en www-data.
CMD ["/usr/local/bin/lam-entrypoint.sh"]
