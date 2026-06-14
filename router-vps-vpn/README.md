# router-vps-vpn — быстрый WireGuard + AdGuard Home для ASUS VPN Fusion

Этот проект нужен, чтобы поднять на VPS отдельный быстрый WireGuard-сервер для домашнего роутера ASUS и не сломать уже настроенные подключения родителей.

Идея простая:

```text
VPS AEZA, Германия
├── старый OpenVPN родителей — не трогаем
├── старый Xray, если есть — не трогаем
└── новый WireGuard wg0 для твоего дома

ASUS дома
├── TV → WireGuard VPN
├── iPhone → WireGuard VPN
├── iPad → WireGuard VPN
└── игровой ПК → обычный интернет без VPN
```

Скрипт ставит:

- WireGuard;
- оптимизацию скорости BBR/fq;
- NAT для выхода клиентов в интернет;
- MSS clamp, чтобы меньше было проблем с MTU;
- firewall UFW;
- AdGuard Home для DNS-фильтрации рекламы;
- готовый файл `client/asus-wireguard.conf` для ASUS.

---

## 0. Что нужно заранее

Тебе нужно:

1. VPS AEZA на Ubuntu.
2. Доступ к веб-консоли AEZA.
3. ASUS с WireGuard Client и VPN Fusion.
4. Домашний интернет.

Рекомендуемый VPS:

```text
2 vCPU
4 GB RAM
60 GB SSD
Ubuntu 22.04 или Ubuntu 24.04
```

Этого достаточно для WireGuard, AdGuard Home и нескольких устройств.

---

## 1. Как зайти в веб-консоль AEZA

Ты не хочешь Termius, поэтому делаем через браузер.

1. Открой сайт AEZA.
2. Зайди в личный кабинет.
3. Открой раздел с серверами.
4. Нажми на свой VPS.
5. Найди кнопку примерно с названием:

```text
Console
VNC
Web Console
Terminal
```

6. Откроется чёрное окно. Это терминал сервера.
7. Если попросит логин, введи:

```text
root
```

8. Если попросит пароль, введи пароль от VPS.

Если всё нормально, ты увидишь что-то вроде:

```bash
root@ubuntu:~#
```

Это значит, что ты внутри сервера и можешь вставлять команды.

---

## 2. Важное правило безопасности

Мы не трогаем OpenVPN родителей.

Нельзя удалять:

```text
/etc/openvpn
старые .ovpn профили
старые xray inbound
```

Этот проект создаёт новый сервис:

```text
wg-quick@wg0
```

Он живёт отдельно.

---

## 3. Одна команда установки

Вставь в веб-консоль AEZA одну команду:

```bash
apt update && apt install -y git && git clone https://github.com/ihavenoenem1es/career-bot.git && cd career-bot/router-vps-vpn && cp .env.example .env && bash install.sh .env
```

Скрипт сам:

- определит внешний IP сервера;
- создаст ключи WireGuard;
- поставит WireGuard;
- запустит `wg0`;
- поставит AdGuard Home;
- выведет готовый конфиг для ASUS.

В конце ты увидишь большой блок:

```ini
[Interface]
PrivateKey = ...
Address = 10.44.0.2/32
DNS = 10.44.0.1
MTU = 1420

[Peer]
PublicKey = ...
PresharedKey = ...
Endpoint = ТВОЙ_IP:51820
AllowedIPs = 0.0.0.0/0,::/0
PersistentKeepalive = 25
```

Это и есть конфиг для ASUS.

---

## 4. Где найти конфиг после установки

Если случайно закрыл консоль, зайди снова в папку проекта:

```bash
cd ~/career-bot/router-vps-vpn
cat client/asus-wireguard.conf
```

Команда `cat` просто показывает файл на экране.

Скопируй весь блок от `[Interface]` до конца.

---

## 5. Что значит IP сервера

IP сервера — это внешний адрес VPS в интернете.

Например:

```text
185.111.222.333
```

В конфиге ASUS он стоит в строке:

```ini
Endpoint = 185.111.222.333:51820
```

Это означает: ASUS будет подключаться к твоему VPS на порт WireGuard `51820`.

---

## 6. Настройка ASUS WireGuard

Подключись к ASUS по Wi‑Fi или кабелем.

Открой браузер и введи один из адресов:

```text
http://asusrouter.com
```

или

```text
http://192.168.50.1
```

или

```text
http://192.168.1.1
```

Если не знаешь адрес роутера, открой приложение ASUS Router и посмотри IP шлюза.

Дальше:

1. Войди в админку ASUS.
2. Открой раздел **VPN**.
3. Открой **VPN Fusion**.
4. Нажми **Add profile**.
5. Выбери **WireGuard**.
6. Если есть кнопка **Import**, импортируй файл `asus-wireguard.conf`.
7. Если импорта нет, выбери ручной ввод и вставь данные из файла.
8. Сохрани профиль.
9. Включи профиль.

---

## 7. Как назначить устройства в VPN Fusion

В VPN Fusion не надо включать VPN на весь дом.

Нужно выбрать только нужные устройства.

Рекомендуемая схема:

```text
TV        → WireGuard
iPhone    → WireGuard
iPad      → WireGuard
PC gaming → Internet/WAN/No VPN
```

То есть игровой ПК не пускаем через VPN, чтобы не портить пинг в CS2.

На ASUS это обычно делается так:

1. **VPN** → **VPN Fusion**.
2. Открываешь созданный WireGuard-профиль.
3. В блоке устройств выбираешь нужное устройство.
4. Назначаешь ему маршрут через WireGuard.
5. ПК оставляешь на обычном Internet/WAN.

---

## 8. Проверка, что VPN работает

На устройстве, которое пустил через VPN, открой сайт проверки IP.

Должен показываться IP твоего VPS в Германии.

На сервере можно проверить так:

```bash
cd ~/career-bot/router-vps-vpn
bash scripts/status.sh
```

Или отдельно:

```bash
wg show
```

Если ASUS подключился, в `wg show` будет строка `latest handshake`.

---

## 9. Настройка AdGuard Home

После установки открой:

```text
http://IP_СЕРВЕРА:3000
```

Например:

```text
http://185.111.222.333:3000
```

В мастере настройки:

### Web interface

Можно оставить:

```text
0.0.0.0:3000
```

### DNS server

Лучше выбрать:

```text
127.0.0.1:53
10.44.0.1:53
```

Важно: не делай открытый DNS для всего интернета без необходимости.

### Upstream DNS

Рекомендуемый вариант:

```text
https://dns10.quad9.net/dns-query
https://cloudflare-dns.com/dns-query
```

Можно использовать ControlD DoH endpoint, если у тебя будет подписка ControlD.

---

## 10. Реклама и Twitch

AdGuard Home хорошо режет:

- баннеры;
- трекеры;
- рекламу в приложениях;
- мусорные домены;
- часть рекламных запросов.

Но Twitch и YouTube часто отдают видеорекламу через сложные CDN-механизмы. DNS-фильтр не может гарантировать полное удаление видеорекламы.

Для Twitch через сервер максимум разумного:

1. WireGuard для TV/телефона.
2. AdGuard Home DNS.
3. Фильтры AdGuard + OISD.
4. При желании ControlD как upstream DNS.

---

## 11. Рекомендуемые фильтры AdGuard Home

В AdGuard Home открой:

```text
Filters → DNS blocklists
```

Включи стандартный AdGuard DNS filter.

Дополнительно можно добавить OISD:

```text
https://big.oisd.nl/
```

Не добавляй сразу 20 списков. Чем больше списков, тем больше шанс сломать приложения на TV.

---

## 12. Максимальная скорость WireGuard

Скрипт уже включает:

```text
BBR
fq
MSS clamp
MTU 1420
PersistentKeepalive 25
```

Если видео работает, но иногда зависает, поменяй в ASUS-профиле или в файле:

```ini
MTU = 1420
```

на:

```ini
MTU = 1380
```

Потом сохрани профиль заново.

---

## 13. Как включать и выключать VPN

Самый удобный вариант — через ASUS Router app.

1. Открой приложение ASUS Router.
2. Найди раздел VPN или VPN Fusion.
3. Отключай WireGuard-профиль целиком или убирай отдельные устройства из VPN.

Лучше не выключать весь VPN, а менять маршруты устройств:

```text
TV → VPN / Direct
Phone → VPN / Direct
PC → всегда Direct
```

---

## 14. Как добавить ещё одного клиента

Позже можно будет использовать скрипт:

```bash
bash scripts/add-client.sh phone
```

Он создаст отдельный конфиг для нового устройства. Если файл ещё не добавлен в репозиторий, можно создать нового клиента вручную через повторную установку не надо — лучше дождаться скрипта `add-client.sh`.

---

## 15. Если что-то пошло не так

Проверка WireGuard:

```bash
systemctl status wg-quick@wg0
wg show
```

Проверка firewall:

```bash
ufw status verbose
```

Проверка AdGuard:

```bash
systemctl status AdGuardHome
```

Перезапуск WireGuard:

```bash
systemctl restart wg-quick@wg0
```

---

## 16. Удаление только новой системы

Если надо отключить только новый WireGuard, не трогая OpenVPN родителей:

```bash
systemctl stop wg-quick@wg0
systemctl disable wg-quick@wg0
```

OpenVPN родителей при этом не трогается.

---

## 17. Что не делает этот проект

Он не прошивает роутер.

Он не трогает OpenVPN родителей.

Он не обещает 100% удаления видеорекламы Twitch/YouTube, потому что это технически не гарантируется DNS-фильтрацией.

Он делает быструю и стабильную базу:

```text
VPS → WireGuard → ASUS VPN Fusion → выбранные устройства
```
