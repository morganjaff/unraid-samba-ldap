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

## Déploiement

### 1. GitHub / CI

Poussez ce dépôt sur `github.com/morganjaff/unraid-samba-ldap` (adapter le nom
si besoin — pensez à corriger les références `ghcr.io/morganjaff/...` dans
`docker-compose.yml` et `unraid-templates/my-samba-ldap-bridge.xml` en
conséquence). Le workflow `.github/workflows/build.yml` construit et publie
`ghcr.io/<vous>/samba-ldap-bridge:latest` à chaque push sur `main` touchant
`samba/**`, sur le même principe que votre projet `ionos-ddns` existant.

Le package GHCR doit être rendu public (ou Unraid doit être authentifié à
GHCR) pour que le `docker pull` fonctionne depuis l'array.

### 2. Sur Unraid

1. **OpenLDAP** : importer `unraid-templates/my-openldap.xml` (bouton
   "Add Container" -> icône engrenage -> "Template" en bas, ou déposer le
   XML dans `/boot/config/plugins/dockerMan/templates-user/`). Avant le
   premier démarrage, copier `openldap/bootstrap/schema/samba.schema` et
   les fichiers de `openldap/bootstrap/ldif/custom/` vers les chemins
   `appdata/openldap/bootstrap-schema` et `appdata/openldap/bootstrap-ldif`
   déclarés dans le template.
2. **LAM** : importer `unraid-templates/my-lam.xml`, démarrer, se connecter
   avec `cn=admin,<Base DN>` et le mot de passe admin LDAP, puis créer le
   profil de connexion avec le module "Samba 3/4 Account" activé.
3. **samba-ldap-bridge** : importer
   `unraid-templates/my-samba-ldap-bridge.xml`. Ce conteneur est en réseau
   `br0` (macvlan) par défaut : Unraid demandera une IP fixe à l'ajout,
   assignez-en une sur votre LAN. **Désactivez le SMB natif Unraid**
   (Settings -> SMB) une fois ce conteneur validé, pour éviter toute
   confusion entre les deux systèmes de comptes.

## Points de vigilance (à vérifier avant de considérer que c'est "fini")

### Génération du SID de domaine

L'`entrypoint.sh` génère un SID Samba aléatoire et crée l'entrée
`sambaDomain` dans LDAP **au tout premier démarrage seulement** (il vérifie
sa présence avant). Ne supprimez pas cette entrée LDAP par la suite : elle
identifie votre domaine Samba de façon stable, et sa perte invaliderait
les SID déjà attribués à vos comptes.

### Overlay `smbk5pwd`

Le LDIF `10-base-structure.ldif` active l'overlay `smbk5pwd` sur
`olcDatabase={1}mdb,cn=config` — **cet index peut différer** selon la
configuration exacte d'osixia/openldap. Si le chargement échoue au
démarrage (visible dans les logs du conteneur `openldap`), listez les
bases réelles avec :

```
docker exec openldap ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config \
  "(objectClass=olcDatabaseConfig)" dn
```

et corrigez le DN cible dans le LDIF avant de relancer le conteneur avec
une base de données vierge (ou appliquez le LDIF corrigé manuellement via
`ldapmodify`).

Une fois l'overlay actif, tout changement de `userPassword` (via LAM, via
`ldappasswd`, etc.) régénère automatiquement `sambaNTPassword` — c'est ce
qui fait fonctionner le SSO sans script de synchronisation.

### Alignement UID/GID

Les ACL Unix réelles sur le filesystem doivent correspondre aux
`uidNumber`/`gidNumber` déclarés dans LDAP pour chaque compte
(`posixAccount`/`posixGroup`, gérables depuis LAM). Après création des
comptes, alignez la réalité disque :

```
chown -R <uid>:<gid> /mnt/user/family/<compte>
```

Sans ça, `nslcd` résout bien les noms mais les permissions Unix ne suivent
pas les groupes LDAP déclarés dans `valid users`/`write list`.

### Mot de passe de bind LDAP

Ce dépôt utilise l'admin LDAP (`cn=admin,...`) comme `LDAP_BIND_DN` par
simplicité homelab. Une configuration plus stricte utiliserait un compte
LDAP dédié, en lecture/écriture uniquement sur les attributs Samba
nécessaires — à envisager si ce Samba doit un jour sortir d'un LAN
strictement privé.

### Réseau

Le conteneur `samba-ldap-bridge` est pensé pour tourner en `br0` (IP
dédiée sur le LAN), afin d'éviter tout conflit avec le SMB natif Unraid
sur le port 445. Si vous préférez le bridge Docker classique, désactivez
d'abord le SMB natif Unraid pour libérer le port.

## Gestion des comptes au quotidien

Une fois en place, toute la gestion (ajout/suppression d'utilisateurs et de
groupes, reset de mot de passe) se fait depuis l'interface web de **LAM** —
aucune manipulation LDIF manuelle n'est nécessaire en usage courant.
