FROM osixia/openldap:1.5.0

# L'image osixia embarque déjà le schéma Samba (bootstrap/schema/samba.schema) et
# le charge automatiquement : ne pas en ajouter une copie dans schema/custom, la
# conversion échouerait avec "Duplicate attributeType".
#
# On n'embarque que la structure de base et l'overlay smbk5pwd.
COPY bootstrap/ldif/custom/ /container/service/slapd/assets/config/bootstrap/ldif/custom/

# Sans cela, le script de démarrage d'osixia supprime des fichiers internes
# après le premier init, puis plante au redémarrage suivant.
ENV LDAP_REMOVE_CONFIG_AFTER_SETUP=false
# Schéma NIS classique (posixGroup structurel) : requis pour que LAM puisse créer
# un groupe posixGroup seul. En RFC2307bis, posixGroup est auxiliaire et exige
# une classe structurelle en plus (groupOfNames), ce qui complique la gestion.
ENV LDAP_RFC2307BIS_SCHEMA=false
