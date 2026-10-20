#!/bin/bash
# =============================================================================
# Add Email User Script
# Usage: ./add-user.sh user@domain.com
# =============================================================================

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <email-address>"
  echo "Example: $0 john@clario.codes"
  exit 1
fi

EMAIL="$1"
echo "Creating email user: ${EMAIL}"

# Generate password
read -sp "Enter password for ${EMAIL}: " PASSWORD
echo ""
if [ -z "$PASSWORD" ]; then
  echo "Password cannot be empty!"
  exit 1
fi

# Generate hash
HASH=$(doveadm pw -s SHA512-CRYPT -p "${PASSWORD}")

# Add to users file
if grep -q "^${EMAIL}:" /etc/dovecot/users 2>/dev/null; then
  echo "User already exists! Updating password..."
  sed -i "s|^${EMAIL}:.*|${EMAIL}:${HASH}|" /etc/dovecot/users
else
  echo "${EMAIL}:${HASH}" >> /etc/dovecot/users
fi

chmod 640 /etc/dovecot/users
chown dovecot:dovecot /etc/dovecot/users

# Create mail directory
DOMAIN=$(echo "${EMAIL}" | cut -d'@' -f2)
LOCAL=$(echo "${EMAIL}" | cut -d'@' -f1)
MAILDIR="/var/vmail/${DOMAIN}/${LOCAL}/Maildir"

mkdir -p "${MAILDIR}"/{cur,new,tmp}
chown -R vmail:vmail "/var/vmail/${DOMAIN}"

echo ""
echo "✅ User created successfully!"
echo "   Email:    ${EMAIL}"
echo "   Maildir:  ${MAILDIR}"
echo ""
echo " IMAP Settings:"
echo "   Server:   mail.${DOMAIN}"
echo "   Port:     993 (IMAP SSL) / 995 (POP3 SSL)"
echo "   Username: ${EMAIL}"
echo "   Password: (the one you entered)"
