#!/bin/bash
# =============================================================================
# Mail Server Setup Script for Ubuntu 24.04/26.04
# Stack: Postfix + Dovecot + OpenDKIM
# Domain: clario.codes (change as needed)
# =============================================================================

set -e
export DEBIAN_FRONTEND=noninteractive

# --------------- CONFIGURATION (EDIT THESE) ---------------
DOMAIN="clario.codes"
MAILHOST="mail.clario.codes"
SERVER_IP="103.217.122.70"  # Your server public IP
# ----------------------------------------------------------

echo "=========================================="
echo " Mail Server Setup for ${DOMAIN}"
echo "=========================================="

# ---------- 1. Install Packages ----------
echo "[1/8] Installing packages..."
apt-get update -qq
apt-get install -y -qq postfix dovecot-imapd dovecot-pop3d dovecot-lmtpd opendkim opendkim-tools openssl

# ---------- 2. SSL Certificate ----------
echo "[2/8] Generating SSL certificate..."
mkdir -p /etc/ssl/mail
if [ ! -f /etc/ssl/mail/mail.crt ]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout /etc/ssl/mail/mail.key -out /etc/ssl/mail/mail.crt \
    -subj "/CN=${MAILHOST}" \
    -addext "subjectAltName=DNS:${MAILHOST},DNS:${DOMAIN}"
  chmod 600 /etc/ssl/mail/mail.key
fi
echo "  SSL cert generated at /etc/ssl/mail/"

# ---------- 3. Postfix ----------
echo "[3/8] Configuring Postfix..."
cat > /etc/postfix/main.cf <<EOF
smtpd_banner = \$myhostname ESMTP
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 3.6

myhostname = ${MAILHOST}
mydomain = ${DOMAIN}
myorigin = \$mydomain
mydestination = \$myhostname, localhost.\$mydomain, localhost
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = ipv4

alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases

smtpd_tls_cert_file = /etc/ssl/mail/mail.crt
smtpd_tls_key_file = /etc/ssl/mail/mail.key
smtpd_tls_security_level = may
smtpd_tls_auth_only = no
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_security_level = may
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination

smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes

milter_default_action = accept
milter_protocol = 6
smtpd_milters = unix:/run/opendkim/opendkim.sock
non_smtpd_milters = unix:/run/opendkim/opendkim.sock

virtual_transport = lmtp:unix:private/dovecot-lmtp
virtual_mailbox_domains = ${DOMAIN}
virtual_mailbox_maps = hash:/etc/postfix/virtual
EOF

# Master.cf - restore default and enable submission
cp /usr/share/postfix/master.cf.debian /etc/postfix/master.cf 2>/dev/null || \
  cp /etc/postfix/master.cf.proto /etc/postfix/master.cf 2>/dev/null || true
sed -i 's/^#submission/submission/; s/^#submissions/submissions/' /etc/postfix/master.cf

echo "@${DOMAIN} postmaster@${DOMAIN}" > /etc/postfix/virtual
postmap /etc/postfix/virtual
echo "postmaster: root" > /etc/aliases
newaliases

# ---------- 4. Dovecot ----------
echo "[4/8] Configuring Dovecot..."
groupadd -r vmail 2>/dev/null || true
useradd -r -g vmail -d /var/vmail -s /usr/sbin/nologin vmail 2>/dev/null || true
mkdir -p /var/vmail/${DOMAIN}
chown -R vmail:vmail /var/vmail

cat > /etc/dovecot/dovecot.conf <<EOF
dovecot_config_version = 2.4.0
dovecot_storage_version = 2.4.0

protocols = imap pop3 lmtp
listen = *, ::
auth_allow_cleartext = yes
auth_mechanisms = plain login

mail_driver = maildir
mail_home = /var/vmail/%{user|domain}/%{user|username}
mail_path = %{home}/Maildir

namespace inbox {
  inbox = yes
}

ssl = yes
ssl_server_cert_file = /etc/ssl/mail/mail.crt
ssl_server_key_file = /etc/ssl/mail/mail.key

passdb passwd-file {
  default_password_scheme = SHA512-CRYPT
  auth_username_format = %{user}
  passwd_file_path = /etc/dovecot/users
}

userdb static {
  fields {
    uid = vmail
    gid = vmail
    home = /var/vmail/%{user|domain}/%{user|username}
  }
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
  user = dovecot
}

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

protocol lmtp {
  postmaster_address = postmaster@${DOMAIN}
  auth_username_format = %{user}
}
EOF

touch /etc/dovecot/users
chown dovecot:dovecot /etc/dovecot/users
chmod 640 /etc/dovecot/users

# ---------- 5. OpenDKIM ----------
echo "[5/8] Configuring OpenDKIM..."
mkdir -p /etc/opendkim/keys/${DOMAIN}
if [ ! -f /etc/opendkim/keys/${DOMAIN}/mail.private ]; then
  opendkim-genkey -b 2048 -d ${DOMAIN} -D /etc/opendkim/keys/${DOMAIN} -s mail -v
  chown -R opendkim:opendkim /etc/opendkim
  chmod 700 /etc/opendkim/keys/${DOMAIN}
  chmod 600 /etc/opendkim/keys/${DOMAIN}/mail.private
fi

echo "${DOMAIN} mail:/etc/opendkim/keys/${DOMAIN}/mail.private" > /etc/opendkim/KeyTable
echo "*@${DOMAIN} mail._domainkey.${DOMAIN}" > /etc/opendkim/SigningTable
printf '127.0.0.1\n::1\n%s\n' "${SERVER_IP}" > /etc/opendkim/trustedhosts

cat > /etc/opendkim.conf <<'EOF'
Syslog                  yes
LogWhy                  yes
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/trustedhosts
InternalHosts           refile:/etc/opendkim/trustedhosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
Mode                    sv
PidFile                 /run/opendkim/opendkim.pid
UserID                  opendkim:opendkim
Socket                  local:/run/opendkim/opendkim.sock
UMask                   0002
OversignHeaders         From
EOF

mkdir -p /run/opendkim
chown opendkim:opendkim /run/opendkim
chmod 755 /run/opendkim

# ---------- 6. Firewall ----------
echo "[6/8] Configuring firewall..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q 'Status: active'; then
  ufw allow 25/tcp
  ufw allow 587/tcp
  ufw allow 465/tcp
  ufw allow 993/tcp
  ufw allow 995/tcp
fi

# ---------- 7. Start Services ----------
echo "[7/8] Starting services..."
systemctl restart postfix
systemctl restart dovecot
systemctl restart opendkim
systemctl enable postfix dovecot opendkim

# ---------- 8. Done ----------
echo "[8/8] Setup complete!"
echo ""
echo "=========================================="
echo " Setup Complete!"
echo "=========================================="
echo ""
echo " Next Steps:"
echo " 1. Add DNS records (see README.md)"
echo " 2. Create email users:"
echo "    ./scripts/add-user.sh user@${DOMAIN}"
echo " 3. Set PTR/rDNS with your provider"
echo " 4. Test: send mail to your address"
echo ""
echo " DKIM Public Key:"
cat /etc/opendkim/keys/${DOMAIN}/mail.txt
echo "=========================================="
