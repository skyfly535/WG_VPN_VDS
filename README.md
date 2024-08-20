# IaC установка Wireguard VPN на VPS

[Исходная статья](https://1cloud.ru/help/vpn_manuals/wireguard_vpn_on_vps)

## Установка сервера

Установка серверной части WireGuard на сервере VDS осуществляется при помощи `Ansible`.

Ansible playbook выполняет следующие действия:

1. Устанавливает необходимые пакеты.
2. Настраивает конфигурационные файлы для WireGuard.
3. Запускает и включает сервис WireGuard.

### Playbook: `deploy_wireguard.yml`

```yaml
---
- name: Deploy WireGuard Server
  hosts: wireguard_servers
  become: yes
  tasks:

    - name: Ensure the system is updated
      apt:
        update_cache: yes
        upgrade: dist

    - name: Install WireGuard and required packages
      apt:
        name:
          - wireguard
          - wireguard-tools
          - qrencode
          - linux-headers-$(uname -r)
          - dkms
        state: present

    - name: Enable IP forwarding
      sysctl:
        name: net.ipv4.ip_forward
        value: '1'
        state: present
        reload: yes

    - name: Ensure net.ipv4.ip_forward is enabled on boot
      lineinfile:
        path: /etc/sysctl.conf
        regexp: '^#?net.ipv4.ip_forward='
        line: 'net.ipv4.ip_forward=1'
        state: present

    - name: Create WireGuard configuration directory
      file:
        path: /etc/wireguard
        state: directory
        mode: '0700'

    - name: Generate server private key
      command: wg genkey
      register: server_private_key

    - name: Generate server public key
      command: echo "{{ server_private_key.stdout }}" | wg pubkey
      register: server_public_key

    - name: Generate pre-shared key
      command: wg genpsk
      register: psk

    - name: Retrieve network interface with public IP
      command: ip -o addr show scope global | awk '$4 !~ /^(10|192\.168|172\.(1[6-9]|2[0-9]|3[0-1]))\./ {print $2}' | head -n 1
      register: interface_output
      
    - name: Create WireGuard server config
      template:
        src: wg0.conf.j2
        dest: /etc/wireguard/wg0.conf
        mode: '0600'

    - name: Start WireGuard interface
      command: wg-quick up wg0

    - name: Enable WireGuard to start on boot
      systemd:
        name: wg-quick@wg0
        enabled: yes
        state: started
```


### Templates

#### Файл конфигурации сервера `wg0.conf.j2`

```conf
[Interface]
Address = 10.0.0.1/24
SaveConfig = true
PrivateKey = {{ server_private_key.stdout }}
ListenPort = 51820

# Firewall rules
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o {{ interface_output }} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o {{ interface_output }} -j MASQUERADE

[Peer]
# Client 1
PublicKey = CLIENT_PUBLIC_KEY
PresharedKey = {{ psk.stdout }}
AllowedIPs = 10.0.0.2/32
```

#### Инвентарь: `hosts.yml`

```yaml
all:
    hosts:
        wireguard_servers:
            ansible_host: 196.168.1.1
            ansible_connection: ssh
            ansible_user: root
            ansible_password: qwerty12345
```

### Запуск playbook

Каталог, из которого будет осуществляться запуск ansible-playbook, должен содержать следующие файлы:

-  файл laybook  `deploy_wireguard.yml`.
-  файл шаблона `wg0.conf.j2`.
-  файл инвентаря `hosts.yml`.

Для использования `ssh-подключения с паролями` или pkcs11_provider, требуется установить утилиту `sshpass`. Она нужна для передачи паролей через командную строку.

``` bash
sudo apt-get update
sudo apt-get install sshpass
```

Запуск playbook:

```sh
ansible-playbook -i hosts.yml deploy_wireguard.yml
```

### Примечания

- Убедитесь, что вы заменили `CLIENT_PUBLIC_KEY` в шаблоне `wg0.conf.j2` на реальный публичный ключ клиента.
- Если у вас нет прав суперпользователя на сервере, вам нужно будет настроить Ansible для использования sudo.
- Возможно, вам нужно будет настроить дополнительные правила брандмауэра для разрешения трафика через порт WireGuard.

### `Ansible.cfg` для выполнения  таск на только что созданной ВМ VDS (для реализации другого подхода по развертыванию сервера)

Чтобы написать `ansible.cfg` для выполнения задач на только что созданной ВМ VDS, нужно настроить файл так, чтобы он включал необходимые параметры подключения к удаленной машине. Ниже пример минимального конфигурационного файла `ansible.cfg`:

```ini
[defaults]
inventory = hosts
remote_user = your_user         # Пользователь, с которым будет выполняться подключение (например, root или другой пользователь)
host_key_checking = False       # Отключение проверки хоста для новых серверов
retry_files_enabled = False     # Отключение файлов попыток

[privilege_escalation]
become = True                    # Если нужно повышать привилегии (например, sudo)
become_method = sudo             # Метод повышения привилегий
become_user = root               # Пользователь, от имени которого выполняется повышение привилегий
become_ask_pass = False          # Не запрашивать пароль при sudo

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no  # Отключить проверку ключа хоста SSH
timeout = 30                           # Таймаут подключения в секундах

[loggers]
keys = root

```

### Пояснения:

1. **`[defaults]`**:
   - **`inventory = hosts`**: Указывает файл инвентаря, где перечислены хосты, к которым будет происходить подключение.
   - **`remote_user = your_user`**: Пользователь, от имени которого будет выполнено подключение. Замените `your_user` на имя пользователя, который будет использоваться для подключения (например, `root` или `ansible`).
   - **`host_key_checking = False`**: Отключает проверку ключей SSH, что полезно при первом подключении к новым серверам.
   - **`retry_files_enabled = False`**: Отключает создание файлов повторных попыток выполнения.

2. **`[privilege_escalation]`**:
   - **`become = True`**: Позволяет использовать `sudo` для выполнения задач с привилегиями.
   - **`become_method = sudo`**: Метод повышения привилегий — `sudo`.
   - **`become_user = root`**: Указывает, что повышение привилегий будет выполнено до пользователя `root`.
   - **`become_ask_pass = False`**: Не запрашивать пароль при использовании `sudo`.

3. **`[ssh_connection]`**:
   - **`ssh_args = -o StrictHostKeyChecking=no`**: Отключает проверку ключа хоста SSH, чтобы избежать вопросов о подтверждении нового ключа при первом подключении.
   - **`timeout = 30`**: Устанавливает таймаут подключения в 30 секунд.

### Пример файла инвентаря `hosts`:
```ini
[VPN_Server_WG]
your_vds_ip ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_user=your_user
```
Замените `your_vds_ip` на IP-адрес вашей ВМ, а `your_user` — на имя пользователя для подключения. Если используется SSH-ключ, укажите путь к приватному ключу (`ansible_ssh_private_key_file`).

## Скрипт для создания клиентов Wireguard

```bash
#!/bin/bash

# Название клиента (передается как аргумент к скрипту)
CLIENT_NAME=$1
CLIENT_IP=$2

# Проверка, передано ли имя клиента
if [ -z "$CLIENT_NAME" ]; then
  echo "Пожалуйста, укажите имя клиента."
  echo "Использование: $0 <client_name>"
  exit 1
fi

# Пути к файлам конфигурации WireGuard
WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/wg0.conf"
CLIENT_PRIVATE_KEY="$WG_DIR/${CLIENT_NAME}_privatekey"
CLIENT_PUBLIC_KEY="$WG_DIR/${CLIENT_NAME}_publickey"
CLIENT_CONFIG_FILE="$WG_DIR/${CLIENT_NAME}_wg.conf"

# Генерация пары ключей для клиента
echo "Генерация ключей для клиента $CLIENT_NAME..."
wg genkey | tee $CLIENT_PRIVATE_KEY | wg pubkey | tee $CLIENT_PUBLIC_KEY

# Получение ключей и адреса
CLIENT_PRIVATE_KEY_CONTENT=$(cat $CLIENT_PRIVATE_KEY)
CLIENT_PUBLIC_KEY_CONTENT=$(cat $CLIENT_PUBLIC_KEY)
SERVER_PUBLIC_KEY=$(cat $WG_DIR/publickey)  # Публичный ключ сервера
SERVER_IP="217.196.101.151"  # IP-адрес сервера
SERVER_PORT="51830"  # Порт WireGuard сервера

# Присвоение IP-адреса клиенту (измените диапазон, если нужно)
# CLIENT_IP="10.0.0.2/32"

# Добавление новой секции [Peer] в конфигурационный файл WireGuard
echo "Добавление конфигурации клиента в $WG_CONF..."

echo -e "\n[Peer]" >> $WG_CONF
echo "PublicKey = $CLIENT_PUBLIC_KEY_CONTENT" >> $WG_CONF
echo "AllowedIPs = $CLIENT_IP" >> $WG_CONF

# Создание конфигурационного файла для клиента
echo "Создание конфигурационного файла клиента $CLIENT_CONFIG_FILE..."

cat <<EOF > $CLIENT_CONFIG_FILE
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY_CONTENT
Address = $CLIENT_IP
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 20
EOF

# Перезапуск WireGuard для применения изменений
echo "Перезапуск WireGuard..."
systemctl restart wg-quick@wg0

# Переведение (представление) конфиг файла клиента в QR
qrencode -t ansiutf8 < $CLIENT_CONFIG_FILE

echo "Настройка клиента $CLIENT_NAME завершена."
echo "Конфигурационный файл клиента создан: $CLIENT_CONFIG_FILE"

# Перенос сгенерированных файлов в каталог ConfUsers (по желанию, чтоб все кофиги были в одном месте)
# Каталог предварительно надо создать
mv $CLIENT_PRIVATE_KEY $CLIENT_PUBLIC_KEY $CLIENT_CONFIG_FILE ConfUsers/

# Проверка статуса WireGuard
echo "Проверка статуса WireGuard..."
systemctl status wg-quick@wg0
```

### Использование скрипта:
1. Сохранить скрипт в файл, например `add_wireguard_client.sh` на сервере WireGuard.
2. Сделать его исполняемым:
   ```bash
   chmod +x add_wireguard_client.sh
   ```
3. Запустить скрипт, передав имя и внутренний IP-адрес клиента как аргументы:
   ```bash
   ./add_wireguard_client.sh UserWG "10.0.0.3/32"
   ```

Внутренний IP-адреса клиента необходимо задать ткой, который не будет совпадать с уже ранее созданными клиентами. Проверить ранее созданные можно в файле `/etc/WireGuard/wg0.conf`

### Что делает скрипт:
- Генерирует пару ключей для клиента и сохраняет их в `/etc/WireGuard/`.
- Добавляет новую секцию клиента в файл конфигурации `wg0.conf`.
- Получение публичного ключа сервера: Скрипт считывает публичный ключ сервера из файла `/etc/WireGuard/publickey`.
- IP и порт сервера: В скрипте заданы IP и порт сервера (SERVER_IP и SERVER_PORT).
- Создание конфигурационного файла клиента: После генерации ключей и добавления секции клиента в конфигурационный файл сервера, создаётся конфигурационный файл клиента.
- Переведение (представление) конфиг файла клиента в `QR` (доступен будет в стандартном потоке вывода при выполнении скрипта). 
- Перенос сгенерированных файлов в каталог `ConfUsers`.
- Перезагружает сервис WireGuard для применения изменений.
- Проверяет статус сервиса.