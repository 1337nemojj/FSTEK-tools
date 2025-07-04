#!/bin/bash


# === ЦВЕТА ===
RED=$(tput setaf 1)
GRN=$(tput setaf 2)
YLW=$(tput setaf 3)
CYN=$(tput setaf 6)
RST=$(tput sgr0)

# === ВЫБОР СЛОВАРЯ ===
get_wordlist() {
    if [ -f /usr/share/seclists/Discovery/Web-Content/common.txt ]; then
        echo "/usr/share/seclists/Discovery/Web-Content/common.txt"
    elif [ -f /usr/share/dirb/wordlists/common.txt ]; then
        echo "/usr/share/dirb/wordlists/common.txt"
    elif [ -f /usr/share/wordlists/dirb/common.txt ]; then
        echo "/usr/share/wordlists/dirb/common.txt"
    else
        echo ""
    fi
}

# === ЗАВИСИМОСТИ ===
check_dependencies() {
    echo "${CYN}[*] Проверка установленных инструментов...${RST}"
    REQUIRED=(curl jq searchsploit nmap nikto dirb whatweb arp-scan gobuster nuclei subfinder amass dnsrecon sqlmap ffuf wpscan hydra)
    MISSING=()
    for tool in "${REQUIRED[@]}"; do
        if ! command -v $tool &>/dev/null; then
            echo "${RED}[!] Не установлен: $tool${RST}"
            MISSING+=("$tool")
        else
            echo "${GRN}[+] Найден: $tool${RST}"
        fi
    done

    if [ ${#MISSING[@]} -gt 0 ]; then
        echo "${YLW}[*] Можно установить отсутствующие компоненты: ${MISSING[*]}${RST}"
        echo -n "Установить сейчас? [y/N]: "
        read CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            sudo apt update && sudo apt install -y ${MISSING[*]}
        else
            echo "${RED}[!] Продолжение без зависимостей может вызвать ошибки.${RST}"
        fi
    else
        echo "${GRN}[*] Все зависимости установлены.${RST}"
    fi
}

# === ГЕНЕРАЦИЯ NUCLEI ===
running_nuclei_scan() {
    echo "[*] Запуск nuclei..."
    mkdir -p "$OUTDIR/nuclei"
    URL_LIST="$OUTDIR/nuclei/urls.txt"
    if [ ! -s "$URL_LIST" ]; then
        echo "[!] Нет URL-ов для сканирования nuclei. Пропускаем."
        return
    fi

    nuclei -list "$URL_LIST" \
        -t "$HOME/.local/nuclei-templates" \
        -o "$OUTDIR/nuclei/nuclei_output.txt" \
        -nc -rl 50 -duc -random-agent
}

# === СВОДНЫЙ ОТЧЕТ ===
generate_report() {
    REPORT="$OUTDIR/report.txt"
    echo "[*] Генерация отчета: $REPORT"
    {
        echo "=== ОТЧЕТ АУДИТА ДЛЯ $TARGET ==="
        echo "Дата: $(date)"
        echo "Папка: $OUTDIR"
        echo

        echo "--- NMAP (сервисы) ---"
        cat "$OUTDIR/nmap.txt"
        echo

        echo "--- Слабые места (nmap --script vuln) ---"
        cat "$OUTDIR/nmap_vuln.txt"
        echo

        echo "--- WhatWeb ---"
        cat "$OUTDIR/whatweb.txt"
        echo

        echo "--- Уязвимости (nuclei) ---"
        cat "$OUTDIR/nuclei/nuclei_output.txt"
        echo

        echo "--- SQLMap ---"
        if [ -d "$OUTDIR/sqlmap" ]; then
            grep -h -A 5 'sqlmap identified the following injection point' "$OUTDIR/sqlmap"/* 2>/dev/null || echo "Нет инъекций"
        else
            echo "Нет данных"
        fi
        echo

        echo "--- WPScan ---"
        cat "$OUTDIR"/wpscan_*.json 2>/dev/null | jq -r '.version | "Версия WP: "+(.) // empty' || echo "Нет данных или не WordPress"
        echo

        echo "--- Gobuster (директории) ---"
        cat "$OUTDIR"/gobuster_*.txt 2>/dev/null || echo "Нет данных"

    } > "$REPORT"
    echo "[*] Отчет сохранен: $REPORT"
}
# === ФУНКЦИЯ ЗАПУСКА GOBUSTER ===
run_gobuster() {
    local url="$1"
    local outfile="$2"
    local wordlist="$3"

    gobuster dir \
        -u "$url" \
        -w "$wordlist" \
        -x .php,.html,.bak,.txt \
        -s 200,204,301,302,307,403 \
        -e \
        --no-tls-validation \
        --timeout 10s \
        -t 50 \
        --wildcard \
        -o "$outfile"
}
# === АУДИТ ЦЕЛИ ===
run_audit() {
    TARGET=$1
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    OUTDIR="audit_${TARGET}_${TIMESTAMP}"
    mkdir -p "$OUTDIR"

    echo "${YLW}[*] Аудит цели: $TARGET${RST}"
    echo "[*] Результаты: $OUTDIR"

    nmap -sS -sV -O -T4 "$TARGET" -oN "$OUTDIR/nmap.txt"

    detect_http_services

    WORDLIST=$(get_wordlist)
    if [ -z "$WORDLIST" ]; then
        echo "${RED}[!] Нет подходящего wordlist для gobuster. Установи seclists или dirb.${RST}"
    fi

    URL_LIST="$OUTDIR/nuclei/urls.txt"
    mkdir -p "$OUTDIR/nuclei"
    > "$URL_LIST"

    if [ -s "$OUTDIR/web_ports.txt" ]; then
        while IFS=";" read -r PORT SERVICE PROTO; do
            [ "$PORT" == "Порт" ] && continue
            PORT_CLEAN=$(echo "$PORT" | tr '/' '_')
            PORT_NUM=$(echo "$PORT" | cut -d'/' -f1)

            if [[ "$SERVICE" =~ http|web|ssl|kestrel|nginx|apache|iis ]]; then
                echo "[*] Анализируем $SERVICE на порту $PORT..."
                nikto -host "$TARGET" -port "$PORT_NUM" -output "$OUTDIR/nikto_${PORT_CLEAN}.txt"

                PROTO="http"
                if curl -s --connect-timeout 3 "http://$TARGET:$PORT_NUM" > /dev/null; then
                    PROTO="http"
                elif curl -sk --connect-timeout 3 "https://$TARGET:$PORT_NUM" > /dev/null; then
                    PROTO="https"
                else
                    echo "${YLW}[!] $TARGET:$PORT_NUM не отвечает на HTTP/HTTPS${RST}"
                    continue
                fi

                echo "$PROTO://$TARGET:$PORT_NUM" >> "$URL_LIST"

                if [ -n "$WORDLIST" ]; then
                    run_gobuster "$PROTO://$TARGET:$PORT_NUM" "$OUTDIR/gobuster_${PORT_CLEAN}.txt" "$WORDLIST" 
                fi
                if [ ! -f ~/.wpscan/db/main.db ]; then
                    echo "[*] WPScan: база не найдена, запускаю обновление..."
                    wpscan --update || echo "[!] Не удалось обновить базу wpscan"
                fi

                wpscan --url "$PROTO://$TARGET:$PORT_NUM" --no-update --disable-tls-checks -o "$OUTDIR/wpscan_${PORT_CLEAN}.json"
            else
                echo "[*] Пропущен $SERVICE на порту $PORT_NUM — не веб-сервис"
            fi
        done < "$OUTDIR/web_ports.txt"
    fi

    if [ -s "$URL_LIST" ]; then
        echo "[*] Запуск whatweb по найденным URL..."
        while IFS= read -r URL; do
            echo "--- $URL ---" >> "$OUTDIR/whatweb.txt"
            whatweb "$URL" >> "$OUTDIR/whatweb.txt" 2>/dev/null
        done < "$URL_LIST"
    else
        echo "[!] Нет URL для запуска whatweb"
    fi

    sqlmap -u "http://$TARGET" --crawl=1 --output-dir="$OUTDIR/sqlmap" || true
    nmap -p- --script vuln "$TARGET" -oN "$OUTDIR/nmap_vuln.txt"

    running_nuclei_scan

    generate_report

    echo "${GRN}[*] Аудит завершен. Всё в $OUTDIR${RST}"
}


# === ПОИСК CVE И ЭКСПЛОЙТОВ ===
generate_vuln_report() {
    echo "${CYN}[*] Генерация отчета об уязвимостях...${RST}"
    LAST_SCAN_DIR=$(ls -td audit_* net_scan_* 2>/dev/null | head -n1)
    if [ -z "$LAST_SCAN_DIR" ]; then
        echo "${RED}[!] Нет данных для анализа. Проведи скан сначала.${RST}"
        return
    fi

    OUTFILE="$LAST_SCAN_DIR/vulns_report.csv"
    echo "Сервис;Версия;CVE ID;Описание;CVSS;Exploit (ExploitDB)" > "$OUTFILE"

    grep -rhoP '\b([a-zA-Z][a-zA-Z0-9._+-]{2,})\s([0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?)\b' "$LAST_SCAN_DIR"/*.txt | \
    grep -viE 'for|host|in|src|port|dst|mac' | sort -u | while read -r ENTRY; do
        NAME=$(echo "$ENTRY" | awk '{print $1}')
        VERSION=$(echo "$ENTRY" | awk '{print $2}')
        QUERY="$NAME $VERSION"

        echo "[*] Обработка: $QUERY"

        ENCODED_QUERY=$(echo "$QUERY" | sed 's/ /%20/g')
        NVD_DATA=$(curl -s -w "\n%{http_code}" "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=$ENCODED_QUERY&resultsPerPage=1")

        HTTP_CODE=$(echo "$NVD_DATA" | tail -n1)
        JSON_BODY=$(echo "$NVD_DATA" | head -n -1)

        if [ "$HTTP_CODE" != "200" ]; then
            echo "[!] Ошибка HTTP $HTTP_CODE при запросе: $QUERY"
            continue
        fi

        if echo "$JSON_BODY" | jq empty 2>/dev/null; then
            :
        else
            echo "[!] Ошибка парсинга JSON для $QUERY"
            echo "$JSON_BODY" > "$LAST_SCAN_DIR/debug_${NAME}_${VERSION}.json"
            continue
        fi

        if [ "$(echo "$JSON_BODY" | jq '.vulnerabilities | length')" -eq 0 ]; then
            echo "[!] Нет CVE для $QUERY"
            continue
        fi

        CVE_ID=$(echo "$JSON_BODY" | jq -r 'try .vulnerabilities[0].cve.id // empty')
        DESC=$(echo "$JSON_BODY" | jq -r 'try .vulnerabilities[0].cve.descriptions[0].value // empty')
        CVSS=$(echo "$JSON_BODY" | jq -r 'try .vulnerabilities[0].cve.metrics.cvssMetricV31[0].cvssData.baseScore // empty')

        SPLT=$(searchsploit -t "$QUERY" | grep -v '\-\-' | grep -v '^$' | head -n1 | awk -F'|' '{print $2}' | xargs)

        echo "$NAME;$VERSION;$CVE_ID;$DESC;$CVSS;$SPLT" >> "$OUTFILE"
        sleep 6
    done

    echo "${GRN}[*] Отчет сохранен в: $OUTFILE${RST}"
}

# === СЕТЕВАЯ РАЗВЕДКА ===
print_netinfo() {
    echo "${CYN}========== СЕТЕВАЯ ИНФОРМАЦИЯ ==========${RST}"
    ip a
    ip route
    ip -4 addr show | grep inet
    arp -a

    IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
    MYCIDR=$(ip -o -f inet addr show "$IFACE" | awk '{print $4}')

    echo "[*] Интерфейс: $IFACE"
    echo "[*] Сеть: $MYCIDR"

    echo "[*] Запуск Nmap Ping Sweep..."
    nmap -sn --host-timeout 10s --max-retries 2 --max-rtt-timeout 300ms -T3 "$MYCIDR" -oN netinfo_nmap_sweep.txt

    echo "[*] Запуск ARP-Scan..."
    sudo arp-scan --interface="$IFACE" "$MYCIDR" > netinfo_arp_scan.txt

    echo "${CYN}=========================================${RST}"
}

# === ОПРЕДЕЛЕНИЕ ВЕБ-СЕРВИСОВ ===
detect_http_services() {
    echo "[*] Определение веб-сервисов на $TARGET..."
    WEB_PORTS_FILE="$OUTDIR/web_ports.txt"
    echo "Порт;Сервис;Протокол" > "$WEB_PORTS_FILE"

    nmap -p- -sV --open --reason -T4 "$TARGET" -oN "$OUTDIR/http_detect_scan.txt"

    awk '/^[0-9]+\/tcp/ && /open/ && /http|ssl|https|nginx|apache/i' "$OUTDIR/http_detect_scan.txt" | while read line; do
        PORT=$(echo "$line" | awk '{print $1}')
        SERVICE=$(echo "$line" | awk '{for(i=3;i<=NF;++i) printf "%s ", $i; print ""}' | xargs)
        echo "$PORT;$SERVICE;tcp" >> "$WEB_PORTS_FILE"
    done

    COUNT=$(wc -l < "$WEB_PORTS_FILE")
    if [ "$COUNT" -gt 1 ]; then
        echo "${GRN}[*] Обнаружено $(($COUNT - 1)) веб-сервисов. См. $WEB_PORTS_FILE${RST}"
    else
        echo "${YLW}[*] Веб-сервисы не найдены.${RST}"
    fi
}

# === СКАНИРОВАНИЕ ВСЕЙ СЕТИ ===
scan_whole_network() {
    echo "${CYN}========== СКАНИРОВАНИЕ ВСЕЙ СЕТИ ==========${RST}"

    IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
    MYCIDR=$(ip -o -f inet addr show "$IFACE" | awk '{print $4}')
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    OUTDIR="net_scan_$TIMESTAMP"
    mkdir -p "$OUTDIR"

    echo "[*] Интерфейс: $IFACE"
    echo "[*] Сеть: $MYCIDR"

    nmap -sn --host-timeout 10s --max-retries 2 --max-rtt-timeout 300ms -T3 "$MYCIDR" -oG "$OUTDIR/hosts.gnmap"
    grep "Up" "$OUTDIR/hosts.gnmap" | awk '{print $2}' > "$OUTDIR/live_hosts.txt"
    echo "[*] Найдено $(wc -l < "$OUTDIR/live_hosts.txt") активных хостов"

    sudo arp-scan --interface="$IFACE" "$MYCIDR" > "$OUTDIR/arp-scan.txt"

    echo "[*] Начинаем сканирование каждого хоста..."
    echo "Хост;MAC;Вендор;Открытые порты;ОС;Службы" > "$OUTDIR/summary.csv"
    > "$OUTDIR/slow_hosts.log"
    > "$OUTDIR/failed_hosts.txt"

    while read IP; do
        echo "  -> Сканируем $IP"
        timeout 90s nmap -sS -sV -O -T3 --host-timeout 60s --max-retries 2 "$IP" -oN "$OUTDIR/$IP.txt"
        if [ $? -ne 0 ]; then
            echo "$IP" >> "$OUTDIR/failed_hosts.txt"
            echo "[!] $IP — превышен таймаут, добавлен в failed_hosts.txt" | tee -a "$OUTDIR/slow_hosts.log"
            continue
        fi

        MAC=$(grep -i "$IP" "$OUTDIR/arp-scan.txt" | awk '{print $2}')
        VENDOR=$(grep -i "$IP" "$OUTDIR/arp-scan.txt" | cut -f3-)

        PORTS=$(grep "^PORT" -A 20 "$OUTDIR/$IP.txt" | grep open | awk '{print $1}' | paste -sd "," -)
        OS=$(grep "OS details" "$OUTDIR/$IP.txt" | cut -d: -f2- | xargs)
        SVCS=$(grep "^PORT" -A 20 "$OUTDIR/$IP.txt" | grep open | awk '{print $3}' | sort | uniq | paste -sd "," -)

        echo "$IP;$MAC;$VENDOR;$PORTS;$OS;$SVCS" >> "$OUTDIR/summary.csv"
    done < "$OUTDIR/live_hosts.txt"

    echo "${GRN}[*] Готово. Сводка: $OUTDIR/summary.csv${RST}"
    echo "[*] Медленные/пропущенные хосты: $OUTDIR/failed_hosts.txt"
}

# === КАТЕГОРИЗАЦИЯ УСТРОЙСТВ ===
tag_device_types() {
    INPUT_FILE="$1"
    OUTPUT_FILE="${INPUT_FILE%.csv}_tagged.csv"

    echo "Хост;MAC;Вендор;Открытые порты;ОС;Службы;Тип устройства" > "$OUTPUT_FILE"

    tail -n +2 "$INPUT_FILE" | while IFS=";" read -r IP MAC VENDOR PORTS OS SERVICES; do
        TYPE="Неизвестно"

        if echo "$VENDOR" | grep -i -E "tplink|mikrotik|dlink|zyxel|cisco" >/dev/null; then
            TYPE="Роутер"
        elif echo "$VENDOR" | grep -i -E "hikvision|dahua|uniview|axis" >/dev/null || echo "$SERVICES" | grep -i -E "rtsp|http|https" | grep -i cam >/dev/null; then
            TYPE="Камера"
        elif echo "$OS" | grep -i -E "Windows|Linux|Mac|Unix" >/dev/null || echo "$SERVICES" | grep -i -E "ssh|rdp|smb" >/dev/null; then
            TYPE="Компьютер"
        fi

        echo "$IP;$MAC;$VENDOR;$PORTS;$OS;$SERVICES;$TYPE" >> "$OUTPUT_FILE"
    done

    echo "${GRN}[*] Типы устройств добавлены: $OUTPUT_FILE${RST}"
    echo -e "\n${CYN}📊 Сводка по типам:${RST}"
    cut -d';' -f7 "$OUTPUT_FILE" | tail -n +2 | sort | uniq -c
}


# === МЕНЮ ===
show_menu() {
    echo ""
    echo "${GRN}==================== AUDIT HELPER ====================${RST}"
    echo "1) Показать информацию о текущей сети"
    echo "2) Запустить аудит цели"
    echo "3) Сканировать всю локальную сеть и собрать сводку"
    echo "4) Фильтровать устройства по типу (роутеры, камеры, ПК)"
    echo "5) Сформировать отчет об уязвимостях (NVD + ExploitDB)"
    echo "6) Проверить систему на наличие всех зависимостей"
    echo "0) Выйти"
    echo "======================================================"
    echo -n "Выбор: "
    read CHOICE

    case "$CHOICE" in
        1) print_netinfo ;;
        2) echo -n "Введите цель (IP или домен): "; read TARGET; run_audit "$TARGET" ;;
        3) scan_whole_network ;;
        4)
            LAST_SUMMARY=$(ls -t net_scan_*/summary.csv 2>/dev/null | head -n1)
            if [ -z "$LAST_SUMMARY" ]; then
                echo "${RED}[!] Нет файла summary.csv. Сначала просканируй сеть.${RST}"
            else
                tag_device_types "$LAST_SUMMARY"
            fi ;;
        5) generate_vuln_report ;;
        6) check_dependencies ;;
        0) echo "Выход." ; exit 0 ;;
        *) echo "Неверный выбор." ;;
    esac
}

# === ЦИКЛ ===
while true; do
    show_menu
done
