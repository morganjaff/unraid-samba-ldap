# Image LAM dérivée : s'initialise seule sur un volume de configuration vide
# (remplace l'ancien script lam/seed-config.sh et son conteneur jetable).
FROM ghcr.io/ldapaccountmanager/lam:stable

USER root

# Copie de référence de la configuration livrée dans l'image : le volume monté
# sur /var/lib/ldap-account-manager/config la masque, on la garde ailleurs.
# -L : config.cfg est un lien symbolique vers /etc/ldap-account-manager/.
RUN mkdir -p /opt/lam-defaults \
 && cp -aL /var/lib/ldap-account-manager/config /opt/lam-defaults/config

COPY lam-entrypoint.sh /usr/local/bin/lam-entrypoint.sh
RUN chmod 755 /usr/local/bin/lam-entrypoint.sh

# ENTRYPOINT (dumb-init) hérité de l'image de base ; seul le CMD change.
# Le script démarre en root (pour préparer le volume), puis passe en www-data.
CMD ["/usr/local/bin/lam-entrypoint.sh"]
