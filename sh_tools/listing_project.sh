#!/bin/bash

ROOT_DIR=$(pwd)
STATS_FILE="Общая информация"
LISTING_FILE="Описание программы. Приложение А"

# Определение языка по расширению
detect_language() {
    filename="$1"
    ext="${filename##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
        py) echo "Python" ;;
        ipynb) echo "Jupyter Notebook" ;;
        js) echo "JavaScript" ;;
        jsx) echo "JavaScript (React JSX)" ;;
        ts) echo "TypeScript" ;;
        tsx) echo "TypeScript (React TSX)" ;;
        java) echo "Java" ;;
        kt) echo "Kotlin" ;;
        kts) echo "Kotlin Script" ;;
        scala) echo "Scala" ;;
        groovy) echo "Groovy" ;;
        go) echo "Go" ;;
        rs) echo "Rust" ;;
        cpp | cc | cxx) echo "C++" ;;
        hpp | hxx | hh) echo "C++ Header" ;;
        h) echo "C/C++ Header" ;;
        c) echo "C" ;;
        cs) echo "C#" ;;
        vb) echo "Visual Basic .NET" ;;
        swift) echo "Swift" ;;
        m) echo "Objective-C" ;;
        mm) echo "Objective-C++" ;;
        php) echo "PHP" ;;
        html | htm) echo "HTML" ;;
        css | scss | sass) echo "CSS / SCSS / SASS" ;;
        less) echo "LESS" ;;
        json) echo "JSON" ;;
        jsonc) echo "JSON with Comments" ;;
        yaml | yml) echo "YAML" ;;
        xml) echo "XML" ;;
        md | markdown) echo "Markdown" ;;
        txt) echo "Plain Text" ;;
        toml) echo "TOML" ;;
        ini | cfg | conf) echo "INI / Config" ;;
        env) echo ".env File" ;;
        dockerfile | docker) echo "Dockerfile" ;;
        sh) echo "Shell Script" ;;
        bash) echo "Bash Script" ;;
        zsh) echo "Zsh Script" ;;
        fish) echo "Fish Shell Script" ;;
        bat | cmd) echo "Windows Batch" ;;
        ps1) echo "PowerShell" ;;
        sql) echo "SQL" ;;
        pl | pm) echo "Perl" ;;
        rb) echo "Ruby" ;;
        r) echo "R" ;;
        lua) echo "Lua" ;;
        dart) echo "Dart" ;;
        elm) echo "Elm" ;;
        clj | cljs | cljc) echo "Clojure" ;;
        lisp | el) echo "Lisp / Emacs Lisp" ;;
        ex | exs) echo "Elixir" ;;
        erl | hrl) echo "Erlang" ;;
        nim) echo "Nim" ;;
        zig) echo "Zig" ;;
        vala) echo "Vala" ;;
        asm | s | S) echo "Assembly" ;;
        wasm) echo "WebAssembly" ;;
        make | mk) echo "Makefile" ;;
        cmake | CMakeLists.txt) echo "CMake" ;;
        build.gradle | gradle) echo "Gradle Build Script" ;;
        pom.xml) echo "Maven Project" ;;
        tsconfig.json) echo "TypeScript Config" ;;
        package.json) echo "Node Package Config" ;;
        requirements.txt) echo "Python Requirements" ;;
        pyproject.toml) echo "Python Project Config (PEP 518)" ;;
        setup.py) echo "Python Setup Script" ;;
        lock | yarn.lock | package-lock.json) echo "Dependency Lock File" ;;
        log) echo "Log File" ;;
        csv) echo "CSV (Comma-separated values)" ;;
        tsv) echo "TSV (Tab-separated values)" ;;
        pdf) echo "PDF Document" ;;
        doc | docx) echo "Microsoft Word Document" ;;
        xls | xlsx) echo "Microsoft Excel Spreadsheet" ;;
        ppt | pptx) echo "Microsoft PowerPoint" ;;
        other) echo "Other" ;;
        *) echo "Other" ;;
    esac
}

# Категория по размеру
get_size_category() {
    size_kb="$1"
    if (( $(echo "$size_kb == 0" | bc -l) )); then echo "0 KB"
    elif (( $(echo "$size_kb <= 5" | bc -l) )); then echo "1–5 KB"
    elif (( $(echo "$size_kb <= 10" | bc -l) )); then echo "6–10 KB"
    elif (( $(echo "$size_kb <= 50" | bc -l) )); then echo "11–50 KB"
    elif (( $(echo "$size_kb <= 100" | bc -l) )); then echo "51–100 KB"
    else echo ">100 KB"
    fi
}

# Выбор директории
echo "Выберите директорию для сканирования:"
echo "0) Вся текущая директория ($ROOT_DIR)"
i=1
dirs=()
for d in */; do
    dirs+=("${d%/}")
    echo "$i) ${d%/}"
    ((i++))
done

read -p "Введите номер пункта: " choice

if [[ "$choice" == "0" ]]; then
    TARGET_DIR="$ROOT_DIR"
elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#dirs[@]} )); then
    TARGET_DIR="$ROOT_DIR/${dirs[$((choice-1))]}"
else
    echo "Неверный выбор. Выход."
    exit 1
fi

FILES=$(find "$TARGET_DIR" -type f)
TOTAL_FILES=$(echo "$FILES" | wc -l)
TOTAL_SIZE=0
declare -A LANG_COUNTS
declare -A LANG_SIZES
declare -A SIZE_BUCKETS

echo "======== Листинг файлов ========" > "$LISTING_FILE"

COUNT=0
while read -r FILE; do
    ((COUNT++))
    SIZE_BYTES=$(stat -c%s "$FILE" 2>/dev/null || echo 0)
    SIZE_KB=$(echo "scale=2; $SIZE_BYTES / 1024" | bc)
    LANG=$(detect_language "$FILE")
    SIZE_CATEGORY=$(get_size_category "$SIZE_KB")

    LANG_COUNTS["$LANG"]=$((LANG_COUNTS["$LANG"] + 1))
    LANG_SIZES["$LANG"]=$(echo "${LANG_SIZES["$LANG"]} + $SIZE_KB" | bc)
    SIZE_BUCKETS["$SIZE_CATEGORY"]=$((SIZE_BUCKETS["$SIZE_CATEGORY"] + 1))
    TOTAL_SIZE=$((TOTAL_SIZE + SIZE_BYTES))

    echo "=====" >> "$LISTING_FILE"
    echo "$FILE" >> "$LISTING_FILE"
    echo "-----" >> "$LISTING_FILE"
    cat "$FILE" >> "$LISTING_FILE"
    echo -e "\n" >> "$LISTING_FILE"

    PERCENT=$((COUNT * 100 / TOTAL_FILES))
    echo -ne "Обработка файлов: $COUNT / $TOTAL_FILES [$PERCENT%]\r"
done <<< "$FILES"

TOTAL_SIZE_KB=$(echo "scale=2; $TOTAL_SIZE / 1024" | bc)

# Вывод статистики
{
    echo ""
    echo "======== Информация о проекте ========"
    echo "Каталог сканирования: $TARGET_DIR"
    echo "Всего файлов: $TOTAL_FILES"
    echo "Общий размер (в байтах): $TOTAL_SIZE"
    echo "Общий размер (в KB): $TOTAL_SIZE_KB"
    echo ""
    echo "=== Статистика по языкам ==="
    printf "%-20s | %-6s | %-10s | %-15s | %-10s\n" "Язык" "Файлов" "% от всех" "Общий размер (KB)" "% объема"
    echo "-------------------------------------------------------------------------------"
    for LANG in "${!LANG_COUNTS[@]}"; do
        COUNT=${LANG_COUNTS[$LANG]}
        SIZE=${LANG_SIZES[$LANG]}
        COUNT_PCT=$(echo "scale=2; 100 * $COUNT / $TOTAL_FILES" | bc)
        SIZE_PCT=$(echo "scale=2; 100 * $SIZE / $TOTAL_SIZE_KB" | bc)
        printf "%-20s | %-6d | %-10s | %-15s | %-10s\n" "$LANG" "$COUNT" "$COUNT_PCT%" "$SIZE" "$SIZE_PCT%"
    done

    echo ""
    echo "=== Распределение по размерам файлов ==="
    printf "%-15s | %-6s\n" "Категория" "Кол-во"
    echo "-------------------------------"
    for CAT in "${!SIZE_BUCKETS[@]}"; do
        printf "%-15s | %-6d\n" "$CAT" "${SIZE_BUCKETS[$CAT]}"
    done
} | tee "$STATS_FILE"

echo -e "\nГотово!"
echo "Статистика сохранена в '$STATS_FILE'"
echo "Листинг сохранён в '$LISTING_FILE'"
