#!/bin/bash

# Конфигурация
LOG_FILE="/var/log/secure"
USER="user-12-49"
ATTEMPTS_THRESHOLD=5  # Количество неудачных попыток
TIME_WINDOW=10        # Временное окно в минутах
BAN_DURATION="24h"    # Длительность блокировки

# Временные файлы
TEMP_IP_FILE="/tmp/suspicious_ips.txt"
LOCK_FILE="/var/lock/ssh_ip_blocker.lock"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Этот скрипт должен запускаться с правами root"
    exit 1
fi

# Проверка блокировки
if [ -f "$LOCK_FILE" ]; then
    echo "Скрипт уже запущен (существует lock-файл: $LOCK_FILE)"
    exit 1
fi

# Создание lock-файла
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT

# Функция для блокировки IP
block_ip() {
    local ip=$1
    if ! firewall-cmd --list-rich-rules | grep -q "source address=\"$ip\""; then
        echo "Блокировка IP: $ip"
        firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ip' reject"
        firewall-cmd --permanent --add-rich-rule="rule family='ipv6' source address='$ip' reject"
        # Для временной блокировки можно использовать:
        # firewall-cmd --add-rich-rule="rule family='ipv4' source address='$ip' reject" --timeout=$BAN_DURATION
    fi
}

# Функция для разблокировки старых IP
unblock_old_ips() {
    # Эта функция может быть расширена для управления временем блокировки
    echo "Проверка устаревших блокировок..."
    # Можно добавить логику для удаления старых правил по истечении времени
}

# Поиск подозрительных IP
find_suspicious_ips() {
    local current_time=$(date +%s)
    local time_limit=$((current_time - TIME_WINDOW * 60))

    # Поиск неудачных попыток входа для указанного пользователя
    awk -v user="$USER" -v limit="$time_limit" '
    function get_timestamp(line) {
        # Парсим дату из лога и конвертируем в timestamp
        "date -d \"" $1 " " $2 " " $3 "\" +%s" | getline ts
        return ts
    }
    /sshd.*Failed password/ && $0 ~ user {
        for(i=1; i<=NF; i++) {
            if($i == "from") {
                ip = $(i+1)
                gsub(/[^0-9.]/, "", ip)
                if(ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                    ts = get_timestamp($0)
                    if(ts >= limit) {
                        print ip
                    }
                }
                break
            }
        }
    }' "$LOG_FILE" | sort | uniq -c | awk -v threshold="$ATTEMPTS_THRESHOLD" '$1 >= threshold {print $2}'
}

# Основная логика
main() {
    echo "Поиск подозрительных IP адресов..."

    # Применяем изменения firewall (если были постоянные правила)
    firewall-cmd --reload >/dev/null 2>&1

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
    firewall-cmd --reload >/dev/null 2>&1

    if [[ $blocked_count -gt 0 ]]; then
        echo "Заблокировано IP адресов: $blocked_count"
    else
        echo "Подозрительных IP не найдено"
    fi

    # Очистка
    rm -f "$TEMP_IP_FILE"
}

# Запуск
echo "=== SSH IP Blocker started ==="
echo "Пользователь: $USER"
echo "Порог попыток: $ATTEMPTS_THRESHOLD"
echo "Временное окно: $TIME_WINDOW минут"
echo "=============================="

main

# Удаление lock-файла
rm -f "$LOCK_FILE"
