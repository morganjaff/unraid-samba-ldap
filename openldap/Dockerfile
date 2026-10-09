FROM osixia/openldap:1.5.0

# Schéma Samba et LDIF de bootstrap embarqués dans l'image : plus aucun
# montage ni copie manuelle dans l'appdata, le bootstrap est identique à
# chaque déploiement.
COPY bootstrap/schema/ /container/service/slapd/assets/config/bootstrap/schema/custom/
COPY bootstrap/ldif/custom/ /container/service/slapd/assets/config/bootstrap/ldif/custom/

# Sans cela, le script de démarrage d'osixia supprime des fichiers internes
# après le premier init, puis plante au redémarrage suivant.
ENV LDAP_REMOVE_CONFIG_AFTER_SETUP=false
ENV LDAP_RFC2307BIS_SCHEMA=true
