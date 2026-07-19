## Microsoft Outlook Remote Code Execution CVE-2024-21413
CVE-2024-21413 Moniker Links — это критическая уязвимость (с оценкой 9.8 по шкале CVSS) удаленного выполнения кода (RCE) и кражи учетных данных, обнаруженная в почтовом клиенте Microsoft Outlook. Паспорт уязвимости: [CVE-2024-21413 (Moniker Link)](https://www.cve.org/CVERecord?id=CVE-2024-21413)

## Отчеты, по которому проводилось исследование уязвимости: 
1. [Check Point research](https://research.checkpoint.com/2024/the-risks-of-the-monikerlink-bug-in-microsoft-outlook-and-the-big-picture/), собственно те, кто нашел уязвимость
2. [Отчет](https://medium.com/@sithuminzin969/understanding-the-microsoft-outlook-vulnerability-cve-2024-21413-moniker-link-53885e5f77bf), основной отчет, из которого взята теория и порядок эксплуатации
3. [CMNatic repository](https://github.com/CMNatic/CVE-2024-21413), репозиторий, из которого удобно взять exploit скрипт

## Суть проблемы
Check Point в своем отчете объясняют, что уязвимость, которую они назвали "Moniker Link", позволяет обойти встроенные средства защиты Outlook от вредоносных ссылок в электронных письмах. Для этого используется протокол `file://` и специальный символ `!` в ссылке для доступа к удаленному SMB-ресурсу злоумышленников. 

В результате происходит передача NTLM-хеша учетной записи пользователя на сервер злоумышленника без каких-либо предупреждений. Полученные учетные данные могут быть использованы для дальнейших атак, например для аутентификации в сети или подбора пароля. Для успешной эксплуатации достаточно, чтобы пользователь открыл письмо в уязвимой версии Outlook.

## Архитектура VMware
1. **Windows 11 (version 23H2)** (Виртуальная машина с уязвимой версией операционной системы Windows и установленным Microsoft Outlook 2019)
2. **Kali linux (version 2026.2)** (виртуальная машина, выполняющая роль удаленного SMB-сервера, необходимого для моделирования сетевого взаимодействия при обработке Moniker-ссылок)
3. **Microsoft office 2019 (Outlook version: 2002 build 12527.22253)**

![[Pasted image 20260717225601.png]]![[Pasted image 20260717225702.png]] ![[Pasted image 20260717230130.png]] ![[Pasted image 20260717230344.png]]  
Настройки ВМ. 

## Реализация уязвимости

В первую очередь поднимем SMB-сервер на Kali. Это можно сделать при помощи Responder или встроенной команды "Impacket-smbserver". Я буду использовать Responder, так как основная цель - продемонстрировать утечку NTLM хэша, Responder специально создан для перехвата именно SMB аутентификации. команда ```sudo responder -I eth0``` откроет Responder на Kali Linux. 
![[Pasted image 20260718142923.png]]
После включения Responder убеждаемся, что в нашей лаборатории Windows может достичь поднятого SMB сервера(одно из условий выполнения уязвимости).
![[Pasted image 20260718143013.png]]
![[Pasted image 20260718134836.png]]
Запустим SMTP сервер на Kali (Postfix + Dovecot). Чтобы доставить письмо в Outlook в «первозданном» виде (если отправить обычным письмом, наверняка Outlook или другой почтовый сервис заблокирует письмо с потенциально опасным типом file://, решено полностью отказаться от интернета и поднять легитимную почту прямо на Kali Linux:
```
sudo apt update && sudo apt install -y postfix dovecot-imapd python3-aiosmtpd python3-dnspython
```
Далее создадим почтовый ящик: 
```
sudo adduser ilja_victim
```
Далее настройки Postfix и Dovecot: 
```
# Указали домены, для которых почта считается локальной
sudo postconf -e "mydestination = kali.local, localhost.localdomain, localhost"

# Включили SASL-аутентификацию и связали её с Dovecot
sudo postconf -e "smtpd_sasl_auth_enable = yes"
sudo postconf -e "smtpd_sasl_type = dovecot"
sudo postconf -e "smtpd_sasl_path = private/auth"
sudo postconf -e "smtpd_sasl_security_options = noanonymous"
sudo postconf -e "broken_sasl_auth_clients = yes"

# Настроили правила доверия для локальной сети стенда
sudo postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

```
Для удобства был создан скрипт **setup_lab.sh**, чтобы запустить используем: 
```
chmod +x /home/kali/setup_lab.sh
sudo /home/kali/setup_lab.sh

```
Для запуска локальной почты, используем: 
```
sudo systemctl start postfix dovecot
```
Используя python-скрипт **CVE_exploit.py** отправим письмо, используя команды: 
```
python3 /home/kali/CVE_exploit.py   # Отправка сформированного HTML-письма
```
![[Pasted image 20260719230221.png]]
В итоге жертва получает следующее письмо: 
![[Pasted image 20260719230512.png]]
При нажатии на письмо происходит следующее: 
![[Pasted image 20260719230714.png]]