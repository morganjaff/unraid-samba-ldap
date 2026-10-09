FROM osixia/openldap:1.5.0

# L'image osixia embarque déjà le schéma Samba et le charge automatiquement :
# ne pas en ajouter une copie dans schema/custom, la conversion échouerait
# avec "Duplicate attributeType".
COPY bootstrap/ldif/custom/ /container/service/slapd/assets/config/bootstrap/ldif/custom/

# Sans cela, le script de démarrage d'osixia supprime des fichiers internes
# après le premier init, puis plante au redémarrage suivant.
ENV LDAP_REMOVE_CONFIG_AFTER_SETUP=false
ENV LDAP_RFC2307BIS_SCHEMA=true
