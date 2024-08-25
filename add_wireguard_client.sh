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
SERVER_IP="111.222.333.444"  # IP-адрес сервера (надо поменять на свой)
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

# Перенос сгенерированных файлов в каталог ConfUsers (по желанию, стоб все кофиги были в одном месте)
# Каталог предварительно надо создать
mv $CLIENT_PRIVATE_KEY $CLIENT_PUBLIC_KEY $CLIENT_CONFIG_FILE ConfUsers/

# Проверка статуса WireGuard
echo "Проверка статуса WireGuard..."
systemctl status wg-quick@wg0
