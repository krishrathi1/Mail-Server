# 📧 Self-Hosted Mail Server

A production-ready self-hosted mail server built with **Postfix**, **Dovecot**, and **OpenDKIM** on Ubuntu Linux.

## 🏗️ Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           OUTGOING MAIL                  │
                    │                                         │
  User ──SMTP──▶   │  Postfix ──▶ OpenDKIM (sign) ──▶ MX     │
  (587/465)        │       │                                │
                    │       ▼                                │
                    │   Recipient Server                     │
                    │   (Gmail, Outlook, etc.)               │
                    └─────────────────────────────────────────┘

                    ┌─────────────────────────────────────────┐
                    │           INCOMING MAIL                  │
                    │                                         │
  Internet ──▶      │  MX ──▶ Postfix ──LMTP──▶ Dovecot      │
  (port 25)         │                           │             │
                    │                           ▼             │
                    │                     Maildir Storage     │
                    │                     /var/vmail/         │
                    │                                         │
  User ──IMAP──▶    │  Dovecot (993/995) ◀── Mail client     │
                    └─────────────────────────────────────────┘
```

## 📦 Components

| Component | Role | Port |
|-----------|------|------|
| **Postfix** | SMTP (send/receive mail) | 25, 587, 465 |
| **Dovecot** | IMAP/POP3 (read mail) + LMTP (delivery) | 993, 995 |
| **OpenDKIM** | DKIM signing (email authentication) | - |
| **OpenSSL** | TLS/SSL encryption | - |

## 🚀 Quick Setup

### 1. Clone & Install

```bash
git clone https://github.com/krishrathi1/Mail-Server.git
cd Mail-Server
chmod +x scripts/setup.sh
sudo ./scripts/setup.sh
```

### 2. Configure DNS

Add these records in your DNS (Cloudflare/Route53/etc.):

| Type | Name | Value | Notes |
|------|------|-------|-------|
| **A** | `mail` | `YOUR_SERVER_IP` | **DNS only** (no proxy!) |
| **MX** | `@` | `mail.yourdomain.com` | Priority: 10 |
| **TXT** | `@` | `v=spf1 mx a:mail.yourdomain.com ip4:YOUR_IP -all` | SPF |
| **TXT** | `mail._domainkey` | *(from /etc/opendkim/keys/*/mail.txt)* | DKIM |
| **TXT** | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:postmaster@yourdomain.com` | DMARC |

### 3. Create Email Users

```bash
sudo ./scripts/add-user.sh john@yourdomain.com
```

### 4. Set PTR/Reverse DNS

Contact your VPS provider to set:
```
YOUR_SERVER_IP → mail.yourdomain.com
```

## 📁 Project Structure

```
Mail-Server/
├── README.md
├── postfix/
│   ├── main.cf          # Postfix main configuration
│   ├── master.cf        # Postfix service definitions
│   └── virtual          # Virtual mailbox mappings
├── dovecot/
│   ├── dovecot.conf     # Dovecot configuration (v2.4 format)
│   └── users.example    # User database format example
├── opendkim/
│   ├── opendkim.conf    # OpenDKIM configuration
│   ├── KeyTable         # DKIM key mapping
│   ├── SigningTable     # DKIM signing rules
│   ├── trustedhosts     # Trusted networks
│   └── dkim-public.txt  # Public key (add to DNS)
├── ssl/                 # SSL certificates (generated)
└── scripts/
    ├── setup.sh         # Main installation script
    ├── add-user.sh      # Create email user
    └── test-mail.sh     # Send test email
```

## ⚙️ Configuration Files

### Postfix (`main.cf`)

Key settings:
- `myhostname` - Your mail server hostname
- `virtual_mailbox_domains` - Domains you host mail for
- `smtpd_milters` - OpenDKIM socket for signing
- `smtpd_sasl_auth_enable` - Enable authentication via Dovecot

### Dovecot (`dovecot.conf`)

Dovecot 2.4+ format:
- `dovecot_config_version = 2.4.0` - **Required first line**
- `mail_driver = maildir` - Storage format
- `passdb passwd-file` - User authentication
- `userdb static` - Virtual users (no system accounts)

### OpenDKIM

- Signs all outgoing mail with DKIM
- Socket: `/run/opendkim/opendkim.sock`
- Keys: `/etc/opendkim/keys/DOMAIN/mail.private`

## 🔐 Security Features

- ✅ TLS encryption (IMAPS/SMTPS)
- ✅ SASL authentication (required for sending)
- ✅ DKIM signing (email authenticity)
- ✅ SPF validation (anti-spoofing)
- ✅ Relay restrictions (anti-spam)
- ✅ Virtual users (no shell access)

## 🧪 Testing

### Test SMTP locally:
```bash
telnet mail.yourdomain.com 25
EHLO test
MAIL FROM:<test@yourdomain.com>
RCPT TO:<your@gmail.com>
DATA
Hello
.
QUIT
```

### Test IMAP:
```bash
openssl s_client -connect mail.yourdomain.com:993
a1 LOGIN user@domain.com password
a2 LIST "" "*"
```

### Check DKIM:
```bash
opendkim-testkey -d yourdomain.com -s mail -vvv
```

## 📊 Monitoring

### Check service status:
```bash
systemctl status postfix dovecot opendkim
```

### View logs:
```bash
journalctl -u postfix -f
journalctl -u dovecot -f
mailq          # Check mail queue
postqueue -f   # Flush queue
```

### Check ports:
```bash
ss -tlnp | grep -E ':25|:587|:465|:993|:995'
```

## ⚠️ Important Notes

### PTR/Reverse DNS
**Required** for email deliverability. Without it, emails may land in spam or get rejected by Gmail/Outlook.

### IP Reputation
New server IPs have no reputation. Expect emails to go to spam initially. Build reputation by:
- Sending to engaged recipients
- Maintaining low bounce rate (<2%)
- Keeping spam complaints low (<0.1%)

### Port 25
Some ISPs block outbound port 25. Check with:
```bash
telnet gmail-smtp-in.l.google.com 25
```

## 🔧 Troubleshooting

| Problem | Solution |
|---------|----------|
| Mail in spam | Set PTR, wait for IP reputation |
| Can't send | Check port 25 not blocked |
| Auth failed | Check `/etc/dovecot/users` permissions |
| DKIM fail | Verify DNS TXT record |
| Connection refused | Check firewall & service status |

## 📚 Resources

- [Postfix Docs](https://www.postfix.org/documentation.html)
- [Dovecot Docs](https://doc.dovecot.org/)
- [OpenDKIM Docs](https://www.opendkim.org/)
- [mail-tester.com](https://www.mail-tester.com/) - Test deliverability

## 📝 License

MIT License - Feel free to use and modify.

---

**Built with ❤️ by [Krish Rathi](https://github.com/krishrathi1)**
