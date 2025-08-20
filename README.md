# IaC установка Wireguard VPN на VPS

[Исходная статья](https://1cloud.ru/help/vpn_manuals/wireguard_vpn_on_vps)

## Про VDS/VPS

Данные конфиги были обкатаны на виртуалках `Ubuntu 20.04` провайдера  [kvmka](https://kvmka.ru/)

## 🚀 Развертывание WireGuard сервера

Установка серверной части WireGuard на сервере VDS осуществляется при помощи `Ansible`.

### 1. Подготовка
- Сервер: Ubuntu 20.04 или 22.04  
- Установлен **Ansible** на управляющем хосте  
- Подготовлен inventory-файл `hosts.yml`

Пример `hosts.yml`:
```yaml
all:
  hosts:
    wireguard_servers:
      ansible_host: 111.222.333.444 # поменять на свой IP сервера
      ansible_connection: ssh
      ansible_user: root
      ansible_password: your_password # указать пароль
````

### 2. Запуск Ansible playbook

```bash
ansible-playbook -i hosts.yml deploy_wireguard.yml
```

### 3. Конфигурация сервера

В процессе плейбук:

* Установит пакеты `wireguard`, `wireguard-tools`, `qrencode`, `dkms`
* Включит `net.ipv4.ip_forward`
* Настроит `wg0.conf` с NAT и forwarding правилами:

  ```ini
  [Interface]
  Address = 10.0.0.1/24
  ListenPort = 51820
  PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o <iface> -j MASQUERADE
  PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o <iface> -j MASQUERADE
  ```
* Запустит и активирует `wg-quick@wg0`

---

## 👥 Управление клиентами (Peers)

### Добавление нового клиента

```bash
sudo /etc/wireguard/add_wireguard_client_new.sh <имя_клиента>
```

Пример:

```bash
sudo /etc/wireguard/add_wireguard_client_new.sh myphone
```

Скрипт:

* сгенерирует ключи (Private/Public/PSK),
* автоматически назначит свободный IP (10.0.0.x/32),
* добавит `[Peer]` в `wg0.conf` и применит его **без рестарта интерфейса**,
* создаст клиентский конфиг в `/etc/wireguard/clients/<имя>.conf`,
* выведет QR-код для быстрого импорта в мобильное приложение WireGuard.

### Клиентский конфиг (`/etc/wireguard/clients/myphone.conf`)

```ini
[Interface]
PrivateKey = <client_private_key>
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = <server_public_key>
PresharedKey = <psk>
Endpoint = <server_public_ip>:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

---

## 🔧 Дополнительно

### Проверка статуса

```bash
sudo wg show
```

### Перезапуск WireGuard вручную

```bash
sudo systemctl restart wg-quick@wg0
```

### Открытие порта в UFW

```bash
sudo ufw allow 51820/udp
```

---

## 📜 Структура проекта

```
hosts.yml                         # Ansible inventory
deploy_wireguard.yml              # Ansible playbook для развертывания сервера
wg0.conf.j2                       # Jinja2-шаблон server конфигурации WireGuard
add_wireguard_client_new.sh       # Скрипт добавления клиента
```

---

## ✅ Тестирование

1. Подними сервер с плейбуком.
2. Добавь клиента через скрипт.
3. На клиенте импортируй конфиг или QR в приложение WireGuard.
4. Проверь:

   ```bash
   ping 10.0.0.1       # пинг до сервера
   curl ifconfig.me    # интернет идёт через VPN
   ```
