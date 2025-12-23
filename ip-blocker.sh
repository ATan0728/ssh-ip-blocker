#!/bin/bash

# Конфигурационный файл
CONFIG_FILE="/etc/ssh-ip-blocker.conf"

# Загрузка конфигурации
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    logger -p auth.warning -t "user-12-49/ssh-ip-blocker" "Config file $CONFIG_FILE not found, using defaults"
    USER="user-12-49"
    ATTEMPTS_THRESHOLD=5
    TIME_WINDOW=10
    BAN_DURATION="24h"
    LOG_FILE="/var/log/secure"
fi

# Временные файлы
TEMP_IP_FILE="/tmp/suspicious_ips.txt"
LOCK_FILE="/var/run/ssh-ip-blocker.lock"

# Функция для записи в системный журнал
log_message() {
    local level=$1
    local message=$2
    logger -p "auth.${level}" -t "user-12-49/ssh-ip-blocker" "$message"
}

# Проверка блокировки
if [ -f "$LOCK_FILE" ]; then
    log_message "warning" "Скрипт уже запущен"
    exit 1
fi

# Создание lock-файла
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; log_message "info" "Скрипт завершил работу"; exit' INT TERM EXIT

log_message "info" "Запуск проверки подозрительных IP-адресов"

# Функция для блокировки IP
block_ip() {
    local ip=$1
    if ! firewall-cmd --list-rich-rules | grep -q "source address=\"$ip\""; then
        log_message "notice" "Блокировка IP: $ip"
        firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ip' reject" 2>/dev/null
        firewall-cmd --permanent --add-rich-rule="rule family='ipv6' source address='$ip' reject" 2>/dev/null
    fi
}

# Поиск подозрительных IP
find_suspicious_ips() {
    # Упрощенная версия для тестирования
    awk -v user="$USER" '
    /sshd.*Failed password/ && $0 ~ user {
        for(i=1; i<=NF; i++) {
            if($i == "from") {
                ip = $(i+1)
                gsub(/[^0-9.]/, "", ip)
                if(ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                    print ip
                }
                break
            }
        }
    }' "$LOG_FILE" | sort | uniq -c | awk -v threshold="$ATTEMPTS_THRESHOLD" '$1 >= threshold {print $2}'
}

# Основная логика
main() {
    log_message "info" "Поиск подозрительных IP адресов..."
   
    # Применяем изменения firewall
    if ! firewall-cmd --reload >/dev/null 2>&1; then
        log_message "err" "Ошибка перезагрузки firewalld"
    fi
   
    # Поиск IP для блокировки
    find_suspicious_ips > "$TEMP_IP_FILE"
   
    local blocked_count=0
    while read -r ip; do
        if [[ -n "$ip" ]]; then
            block_ip "$ip"
            ((blocked_count++))
        fi
    done < "$TEMP_IP_FILE"
   
    # Применяем постоянные правила
    if ! firewall-cmd --reload >/dev/null 2>&1; then
        log_message "err" "Ошибка применения правил firewalld"
    fi
   
    if [[ $blocked_count -gt 0 ]]; then
        log_message "notice" "Заблокировано IP адресов: $blocked_count"
    else
        log_message "info" "Подозрительных IP не найдено"
    fi
   
    # Очистка
    rm -f "$TEMP_IP_FILE"
}

# Запуск
main

# Удаление lock-файла
rm -f "$LOCK_FILE"
log_message "info" "Проверка завершена успешно"
