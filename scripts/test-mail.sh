#!/bin/bash
# =============================================================================
# Test Mail Script
# Usage: ./test-mail.sh recipient@example.com
# =============================================================================

set -e

RECIPIENT="$1"
SENDER="test@clario.codes"

if [ -z "$RECIPIENT" ]; then
  echo "Usage: $0 <recipient-email>"
  echo "Example: $0 your@gmail.com"
  exit 1
fi

echo "Sending test mail from ${SENDER} to ${RECIPIENT}..."

# Send via local Postfix
python3 <<EOF
import smtplib
from email.mime.text import MIMEText

msg = MIMEText("Hello!\\n\\nThis is a test mail from your self-hosted mail server.\\n\\n- Mail Server\\n")
msg["Subject"] = "Test Mail from Mail Server"
msg["From"] = "${SENDER}"
msg["To"] = "${RECIPIENT}"

try:
    with smtplib.SMTP("127.0.0.1", 25, timeout=30) as s:
        s.sendmail("${SENDER}", ["${RECIPIENT}"], msg.as_string())
        print("✅ Mail sent successfully!")
except Exception as e:
    print(f"❌ Error: {e}")
EOF

echo ""
echo "Check delivery status:"
sleep 3
mailq
echo ""
echo "Logs:"
journalctl -u postfix --since "1 min ago" | grep "status=" | tail -5
