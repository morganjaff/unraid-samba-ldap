FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Pré-répondre aux questions debconf de libnss-ldapd pour un build non-interactif
RUN echo "libnss-ldapd libnss-ldapd/nsswitch multiselect passwd, group, shadow" | debconf-set-selections

RUN apt-get update && apt-get install -y --no-install-recommends \
        samba \
        samba-common-bin \
        ldap-utils \
        nslcd \
        libnss-ldapd \
        wsdd \
        gettext-base \
        procps \
        iproute2 \
    && rm -rf /var/lib/apt/lists/*

# nsswitch.conf : résolution des comptes/groupes via LDAP (posixAccount/posixGroup),
# nécessaire pour que smbd/le filesystem résolvent les mêmes uid/gid que LDAP.
COPY nsswitch.conf /etc/nsswitch.conf

COPY templates/ /templates/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && mkdir -p /var/lib/samba/private /var/log/samba

EXPOSE 445/tcp 139/tcp 137/udp 138/udp 3702/udp

ENTRYPOINT ["/entrypoint.sh"]
