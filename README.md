# unraid-samba-ldap

Samba (SMB) authentifié sur un annuaire OpenLDAP, pour un homelab familial sous
Unraid, en remplacement du SMB natif Unraid (comptes locaux uniquement). Les comptes
se gèrent dans une interface web (LAM) et servent à tous les services compatibles LDAP.

```
Client Windows / macOS / Linux
      │  SMB (445)
      ▼
samba-ldap-bridge   Samba en passdb ldapsam, uid/gid résolus par nslcd
      │  LDAP (389)
      ▼
openldap            schéma Samba + overlay smbk5pwd
      ▲
      │  LDAP (389)
lam                 LDAP Account Manager : interface web d'administration
```

Les trois images sont construites automatiquement par GitHub Actions et publiées sur
GHCR (`openldap-samba`, `lam-samba`, `samba-ldap-bridge`). Les comptes et partages
natifs d'Unraid ne sont **pas** utilisés : les deux systèmes sont étanches.

## Contenu du dépôt

```
openldap/                       Image OpenLDAP (dérivée d'osixia) + LDIF de base embarqués
lam/                            Image LAM : s'initialise seule, modules Samba activés d'office
samba/                          Image Samba + LDAP (entrypoint, modèles de configuration)
samba/smb-shares.conf.example   Modèle de partages ([homes], [family], [photos]...)
unraid-templates/*.xml          Templates « Add Container » pour Unraid
docker-compose.yml, .env.example   Déploiement de test hors Unraid
```

## Déploiement sur Unraid

Ordre à respecter : OpenLDAP, puis LAM, puis Samba. Remplacez `192.168.0.253` par l'IP
de votre NAS et `dc=home,dc=lan` par votre Base DN.

### 1. OpenLDAP

Importer `unraid-templates/my-openldap.xml` (Docker → Add Container → choisir le template),
renseigner `LDAP_ADMIN_PASSWORD` et `LDAP_CONFIG_PASSWORD`, puis démarrer. `LDAP_DOMAIN`
(`home.lan`) définit le Base DN (`dc=home,dc=lan`).

Au premier démarrage, l'image crée `ou=people`, `ou=groups` et active l'overlay `smbk5pwd`.
Aucun fichier à copier. Le port 389 est publié sur le NAS.

### 2. LAM (interface d'administration)

Importer `unraid-templates/my-lam.xml`, renseigner `LAM_PASSWORD` (mot de passe maître
de LAM), vérifier `LDAP_SERVER` (`ldap://<IP du NAS>:389`) et `LDAP_BASE_DN`, puis démarrer.

Au premier démarrage, l'image initialise seule sa configuration dans
`/mnt/user/appdata/lam/config` et active les modules Samba 3 (utilisateurs, groupes) et le
type de compte « Samba domains ». Ensuite elle n'y touche plus : les réglages faits dans
l'interface sont conservés. Interface : `http://<IP du NAS>:8081/` (identifiant
`cn=admin,<Base DN>` et mot de passe `LDAP_ADMIN_PASSWORD`).

### 3. Samba (samba-ldap-bridge)

1. **Désactiver le SMB natif d'Unraid** : Settings → SMB → Enable SMB = No. Le conteneur
   tourne en réseau **Host** : il utilise l'IP du NAS et ses ports 445/139/137/138/3702, qui
   seraient sinon en conflit.
2. Importer `unraid-templates/my-samba-ldap-bridge.xml` et renseigner :
   - `LDAP_URI` : `ldap://<IP du NAS>:389` (le nom du conteneur ne se résout pas en mode Host) ;
   - `LDAP_BASE_DN`, `LDAP_BIND_DN` (`cn=admin,<Base DN>`) et `LDAP_BIND_PASSWORD` ;
   - `SAMBA_NETBIOS_NAME` : nom du serveur dans le réseau. **À choisir une fois pour toutes**
     (voir « Points de vigilance »).
3. Les chemins à vérifier : le dossier des partages (par défaut `/mnt/user/users`) et
   `smb-shares.conf` dans `/mnt/user/appdata/samba-ldap-bridge/`. Tout dossier utilisé dans
   un partage doit être monté dans le conteneur, sinon Samba ne le voit pas.
4. Démarrer. Au premier démarrage, l'entrypoint crée l'entrée de domaine Samba
   (nommée d'après `SAMBA_NETBIOS_NAME`) dans LDAP.

### 4. Créer les comptes (dans LAM)

1. **Groupe** (type de compte « Groupes ») : par exemple `family`, avec un GID dans la
   plage 10000-20000. Module Samba : type de groupe « Domain group ».
2. **Utilisateur** (type de compte « Utilisateurs ») :
   - onglet *Personnel* : identifiant, prénom, nom ;
   - onglet *Unix* : UID dans la plage 10000-30000, groupe principal (ex. `family`) ;
   - onglet *Samba 3* : sélectionner le domaine Samba, puis **« Définir le mot de passe »**.
     Le mot de passe SMB n'est écrit que depuis cet onglet, pas depuis l'onglet Unix ;
   - cliquer sur **Enregistrer** en bas de page. Un changement non enregistré n'est pas pris en compte.

### 5. Définir les partages

Éditer `/mnt/user/appdata/samba-ldap-bridge/smb-shares.conf` (modèle :
`samba/smb-shares.conf.example`) puis redémarrer le conteneur.

- **`[homes]`** : un dossier personnel par utilisateur, créé automatiquement à la première
  connexion avec le bon propriétaire (uid LDAP) et le mode 700. Aucune action côté Unraid.
- **Partages communs** (ex. `[data]`) : `valid users = @family`. Le dossier doit appartenir
  au groupe concerné, par exemple `chown :family`, `chmod 2770`, sinon l'écriture échoue.

### 6. Vérifier

```
smbclient //<IP du NAS>/<login> -U <login>
```

Sous Windows : `\\<IP du NAS>`, avec l'identifiant LDAP. Le NAS apparaît aussi dans la section
Réseau de l'explorateur grâce à `wsdd` (mode Host).

## Points de vigilance (à vérifier avant de considérer que c'est "fini")

### Génération du SID de domaine

L'`entrypoint.sh` génère un SID Samba aléatoire et crée l'entrée
`sambaDomain` (nommée d'après le nom NetBIOS) dans LDAP **au tout premier démarrage seulement** (il vérifie
sa présence avant). Ne supprimez pas cette entrée LDAP par la suite : elle
identifie votre domaine Samba de façon stable, et sa perte invaliderait
les SID déjà attribués à vos comptes.

### Overlay `smbk5pwd`

Le module `smbk5pwd.so` est présent dans l'image `osixia/openldap:1.5.0`, et
`cn=module{0},cn=config` / `olcDatabase={1}mdb,cn=config` existent bien : le
LDIF `20-samba-overlay.ldif` est donc valide tel quel.

**Limite à connaître :** l'overlay ne se déclenche que sur l'opération
étendue *Password Modify* (RFC 3062), utilisée par `ldappasswd` et les clients
qui la supportent. Une modification directe de l'attribut `userPassword`
(`ldapmodify`) ne régénère **pas** `sambaNTPassword`. Avec LAM, le module
"Samba 3 account" calcule lui-même le hash NT quand on saisit le mot de
passe dans l'onglet Samba : à tester sur un compte avant d'en créer d'autres.

Vérification de l'overlay :

```
docker exec openldap ldapsearch -x -H ldap://localhost \
  -D "cn=admin,cn=config" -w '<LDAP_CONFIG_PASSWORD>' \
  -b cn=config "(olcOverlay=smbk5pwd)" dn
```

### Dépannage LAM : configuration perdue au redémarrage

Le dossier de configuration de l'image est `/var/lib/ldap-account-manager/config`
(et non `/var/www/html/config`). L'image `lam-samba` y initialise la configuration
si le dossier est vide (il faut alors `LAM_PASSWORD`), puis désactive la
préconfiguration officielle pour ne jamais réécrire vos réglages. Pour repartir de
zéro : arrêter le conteneur et vider `/mnt/user/appdata/lam/config`.

### Dépannage Samba : `NT_STATUS_INVALID_SID`

`pdbedit -L` affichant `sid ... does not belong to our domain`, ou `smbclient`
répondant `NT_STATUS_INVALID_SID`, signifie que les SID des comptes ne sont pas
ceux du domaine que Samba utilise. Un serveur autonome nomme son domaine d'après
son **nom NetBIOS** (pas le workgroup) et relit le SID de l'entrée
`sambaDomainName=<NOM NETBIOS>` à chaque démarrage (visible dans `log.smbd` :
`Resetting SID for domain ...`). L'entrypoint crée donc cette entrée-là, et LAM
doit utiliser **ce** domaine pour les comptes.
Ne pas changer `SAMBA_NETBIOS_NAME` une fois des comptes créés.
Liste des domaines :
`ldapsearch ... "(objectClass=sambaDomain)" sambaDomainName sambaSID`.

### Dépannage OpenLDAP (problèmes rencontrés au déploiement)

- **LAM : `Object class violation - no structural object class provided`** à la
  création d'un groupe : l'annuaire a été initialisé en RFC2307bis, où
  `posixGroup` est auxiliaire. L'image utilise le schéma NIS classique
  (`LDAP_RFC2307BIS_SCHEMA=false`). Ce choix est fixé à la première
  initialisation : pour le changer, supprimer le conteneur, vider `database`
  et `config`, puis recréer.

- **`Duplicate attributeType` / `slaptest conversion failed`** : le schéma Samba
  est déjà inclus dans l'image osixia. Ne pas en ajouter une seconde copie dans
  `bootstrap/schema/custom`.

- **`could not stat config file "/etc/ldap/slapd.conf"`** : `config` et
  `database` ne sont pas dans un état cohérent. Arrêter **et supprimer** le
  conteneur, vider **les deux** dossiers en même temps, puis le recréer.
- **Le bootstrap "réussit" mais rien n'est créé** : le log affiche toujours
  "Add custom bootstrap ldif..." même si un LDIF échoue ou si le dossier est
  vide. Vérifier dans l'image :
  `docker exec openldap ls /container/service/slapd/assets/config/bootstrap/ldif/custom/`
  puis tester les requêtes de la section "Vérification" ci-dessous.
- **`ldapsearch` sur `cn=config`** : se connecter avec `cn=admin,cn=config` et
  `LDAP_CONFIG_PASSWORD`, pas avec l'admin des données.

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

`samba-ldap-bridge` tourne en mode **Host** (IP du NAS, découverte Windows
fonctionnelle, SMB natif Unraid à désactiver). En mode Bridge, le partage
reste accessible par `\\<IP>` mais n'apparaît pas dans le Voisinage réseau
(WS-Discovery en multicast bloqué). Le mode `br0` (IP dédiée) fonctionne aussi,
mais le conteneur ne peut alors pas joindre l'IP du NAS (limite macvlan).

## Gestion des comptes au quotidien

Une fois en place, toute la gestion (ajout/suppression d'utilisateurs et de
groupes, reset de mot de passe) se fait depuis l'interface web de **LAM** —
aucune manipulation LDIF manuelle n'est nécessaire en usage courant.

## Vérification d'un OpenLDAP fraîchement déployé

```
# Schéma Samba chargé
docker exec openldap ldapsearch -x -H ldap://localhost -D "cn=admin,cn=config" \
  -w '<LDAP_CONFIG_PASSWORD>' -b cn=schema,cn=config "(cn={*}samba)" cn

# Structure de base
docker exec openldap ldapsearch -x -H ldap://localhost -D "cn=admin,<BASE_DN>" \
  -w '<LDAP_ADMIN_PASSWORD>' -b "<BASE_DN>" "(objectClass=organizationalUnit)" dn

# Overlay smbk5pwd
docker exec openldap ldapsearch -x -H ldap://localhost -D "cn=admin,cn=config" \
  -w '<LDAP_CONFIG_PASSWORD>' -b cn=config "(olcOverlay=smbk5pwd)" dn
```

Redéploiement à zéro : arrêter **et supprimer** le conteneur, vider `database`
**et** `config` ensemble, puis recréer le conteneur.
