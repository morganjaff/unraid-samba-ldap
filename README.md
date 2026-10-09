# unraid-samba-ldap

Samba (SMB) authentifié sur un annuaire OpenLDAP, pour homelab familial sous
Unraid — en remplacement du SMB natif Unraid (comptes locaux uniquement).

Architecture :

```
Client Windows/macOS
      │
      ▼
samba-ldap-bridge (conteneur dédié, passdb backend = ldapsam)
      │  authentifie via sambaSamAccount, résout uid/gid via nslcd (posixAccount)
      ▼
openldap (schéma Samba + overlay smbk5pwd : synchro auto userPassword -> sambaNTPassword)
      │
      ▼
lam (LDAP Account Manager — interface web d'administration des comptes)
```

Les comptes/partages natifs Unraid (WebGUI, ACL SMB natives) ne sont **pas**
utilisés par ce dispositif : les deux systèmes d'authentification sont
volontairement étanches. Voir la discussion complète dans la conversation
qui a motivé ce dépôt pour le détail de ce choix.

## Contenu du dépôt

```
openldap/bootstrap/schema/samba.schema      Schéma LDAP officiel Samba (chargé une fois)
openldap/bootstrap/ldif/custom/*.ldif       Structure de base + overlay smbk5pwd (chargé une fois)
samba/                                      Image du conteneur Samba+LDAP (Dockerfile, entrypoint, templates)
samba/smb-shares.conf.example               Modèle de définition des partages
docker-compose.yml                          Déploiement de test / hors Unraid
.env.example                                Variables pour docker-compose
unraid-templates/*.xml                      Templates "Add Container" pour Unraid
.github/workflows/build.yml                 CI : build + push de l'image samba-ldap-bridge vers GHCR
```

M** —
aucune manipulation LDIF manuelle n'est nécessaire en usage courant.
