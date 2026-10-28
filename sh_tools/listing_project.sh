#!/usr/bin/env bash
# =============================================================================
# listing_project.sh — статистика файлов проекта и текстовый листинг.
#
# Назначение:
#   Рекурсивно сканирует выбранный каталог, определяет язык или формат файлов,
#   подсчитывает количество, общий размер и распределение по размерам.
#   Распознаёт более 650 расширений, а также специальные имена файлов.
#
# Запуск:
#   bash listing_project.sh                         # интерактивный выбор
#   bash listing_project.sh /путь/к/проекту          # статистика в терминале
#   bash listing_project.sh --save /путь/к/проекту   # сохранить отчёты
#   bash listing_project.sh --output-dir ./отчёты /путь/к/проекту
#   bash listing_project.sh --help                  # справка
#
# Сохранение:
#   По умолчанию файлы отчётов не создаются. Опции --save и --output-dir
#   включают сохранение; --save использует текущий рабочий каталог.
#   «Общая информация» — статистика; «Описание программы. Приложение А» —
#   пути и содержимое текстовых файлов. Существующие отчёты перезаписываются
#   и исключаются из сканирования при включённом сохранении.
#
# Особенности:
#   Сканируются все обычные файлы, включая скрытые и файлы в .git;
#   символические ссылки не обходятся. Бинарные файлы учитываются в статистике,
#   но их содержимое в листинг не включается. Неизвестные форматы — Other.
#   Текстовые файлы включаются целиком, в том числе .env и конфигурации:
#   перед передачей листинга проверьте его на наличие паролей и токенов.
#
# Требования: Bash 3.2+, find, stat (GNU или BSD), awk, grep, tr, mktemp,
#             cat, tee, mkdir, rm. Python и bc для запуска не нужны.
# =============================================================================

usage() {
    cat <<'HELP'
Использование: bash listing_project.sh [--save] [--output-dir КАТАЛОГ] [КАТАЛОГ]
Без каталога предлагается интерактивный выбор.
По умолчанию статистика выводится только в терминал.
  --save                  сохранить статистику и текстовый листинг
  --output-dir КАТАЛОГ     каталог отчётов (также включает сохранение)
  -h, --help              показать справку
Бинарные файлы учитываются в статистике, но их содержимое в листинг не попадает.
HELP
}

SAVE=0
OUTPUT_DIR="$PWD"
TARGET_DIR=
while (( $# )); do
    case "$1" in
        --save) SAVE=1 ;;
        --output-dir)
            if (( $# < 2 )) || [[ -z "$2" ]]; then
                echo 'Не указан каталог отчётов.' >&2; exit 1
            fi
            OUTPUT_DIR="$2"; SAVE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "Неизвестная опция: $1" >&2; exit 1 ;;
        *) if [[ -n "$TARGET_DIR" ]]; then usage >&2; exit 1; fi
           TARGET_DIR="$1" ;;
    esac
    shift
done
if (( $# )); then
    if (( $# != 1 )) || [[ -n "$TARGET_DIR" ]]; then usage >&2; exit 1; fi
    TARGET_DIR="$1"
fi

if [[ -z "$TARGET_DIR" ]]; then
    echo "Выберите директорию для сканирования:"
    echo "0) Вся текущая директория ($PWD)"
    dirs=()
    for d in */; do
        [[ -d "$d" ]] || continue
        dirs+=("${d%/}")
        printf '%d) %s\n' "${#dirs[@]}" "${d%/}"
    done
    read -r -p 'Введите номер пункта: ' choice
    if [[ "$choice" == 0 ]]; then TARGET_DIR="$PWD"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( ${#choice} < 10 )) &&
         (( 10#$choice > 0 && 10#$choice <= ${#dirs[@]} )); then
        TARGET_DIR="$PWD/${dirs[$((10#$choice-1))]}"
    else echo 'Неверный выбор.' >&2; exit 1
    fi
fi
TARGET_DIR=$(cd -- "$TARGET_DIR" && pwd -P) || exit 1
STATS_FILE=
LISTING_FILE=
if (( SAVE )); then
    mkdir -p -- "$OUTPUT_DIR" || exit 1
    OUTPUT_DIR=$(cd -- "$OUTPUT_DIR" && pwd -P) || exit 1
    STATS_FILE="$OUTPUT_DIR/Общая информация"
    LISTING_FILE="$OUTPUT_DIR/Описание программы. Приложение А"
fi

detect_language() {
    local filename="${1##*/}" ext
    filename=$(printf '%s' "$filename" | LC_ALL=C tr '[:upper:]' '[:lower:]')
    case "$filename" in
        dockerfile|dockerfile.*|*.dockerfile|containerfile|containerfile.*) echo Dockerfile; return ;;
        makefile|gnumakefile|bsdmakefile) echo Makefile; return ;;
        cmakelists.txt|cmakecache.txt) echo CMake; return ;;
        package.json) echo 'Node Package Config'; return ;;
        tsconfig*.json|jsconfig*.json) echo 'TypeScript / JavaScript Config'; return ;;
        pom.xml) echo 'Maven Project'; return ;;
        requirements*.txt|constraints*.txt) echo 'Python Requirements'; return ;;
        pyproject.toml|pipfile|setup.cfg|setup.py) echo 'Python Project Config'; return ;;
        cargo.toml) echo 'Rust Project Config'; return ;;
        go.mod|go.sum|go.work) echo 'Go Module / Workspace'; return ;;
        gemfile|rakefile|guardfile|vagrantfile|brewfile) echo Ruby; return ;;
        *.lock|package-lock.json|npm-shrinkwrap.json|*.lockb) echo 'Dependency Lock File'; return ;;
        .env|.env.*|*.env|*.env.*) echo '.env File'; return ;;
        .gitignore|.gitattributes|.gitmodules|.dockerignore|.npmignore|.editorconfig|.browserslistrc) echo 'Project Config'; return ;;
        .bashrc|.bash_profile|.profile|.zshrc|.zprofile) echo 'Shell Config'; return ;;
        .eslintrc|.prettierrc|.babelrc|.npmrc|.yarnrc) echo 'Tool Config'; return ;;
        license|license.*|licence|copying|authors|contributors|readme|changelog|notice) echo 'Project Documentation'; return ;;
        *.tar.gz|*.tar.bz2|*.tar.xz|*.tar.zst) echo 'Compressed TAR Archive'; return ;;
        *.d.ts|*.d.mts|*.d.cts) echo 'TypeScript Declaration'; return ;;
    esac
    ext="${filename##*.}"
    case "$ext" in
        py) echo "Python" ;;
        ipynb) echo "Jupyter Notebook" ;;
        js) echo "JavaScript" ;;
        jsx) echo "JavaScript (React JSX)" ;;
        ts) echo "TypeScript" ;;
        tsx) echo "TypeScript (React TSX)" ;;
        yarn) echo "Yarn" ;;
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
        pyw | pyi | pyx | pxd | pxi) echo 'Python / Cython' ;;
        mjs | cjs | es6) echo 'JavaScript' ;;
        mts | cts) echo 'TypeScript' ;;
        vue) echo 'Vue' ;;
        svelte) echo 'Svelte' ;;
        astro) echo 'Astro' ;;
        mdx) echo 'MDX' ;;
        ejs | hbs | handlebars | mustache | pug | jade | twig | jinja | jinja2 | j2 | njk | liquid | erb | haml | slim) echo 'Template' ;;
        php3 | php4 | php5 | php7 | php8 | phtml | phps) echo 'PHP' ;;
        jsp | jspx) echo 'Java Server Pages' ;;
        asp | aspx | ascx | cshtml | razor) echo 'ASP.NET / Razor' ;;
        xhtml | shtml) echo 'HTML' ;;
        styl | stylus) echo 'Stylus' ;;
        pcss | postcss) echo 'PostCSS' ;;
        graphql | gql) echo 'GraphQL' ;;
        proto) echo 'Protocol Buffers' ;;
        thrift) echo 'Apache Thrift' ;;
        avdl | avsc) echo 'Apache Avro' ;;
        f | f77 | f90 | f95 | f03 | f08 | for | fpp) echo 'Fortran' ;;
        cob | cbl | cpy) echo 'COBOL' ;;
        pas | pp | dpr | lpr | inc) echo 'Pascal / Include' ;;
        ada | adb | ads) echo 'Ada' ;;
        d | di) echo 'D' ;;
        jl) echo 'Julia' ;;
        hs | lhs) echo 'Haskell' ;;
        ml | mli | mll | mly) echo 'OCaml' ;;
        fs | fsi | fsx | fsscript) echo 'F#' ;;
        rkt | rktd | rktl) echo 'Racket' ;;
        scm | ss | sld) echo 'Scheme' ;;
        lsp | cl) echo 'Common Lisp' ;;
        e | eiffel) echo 'Eiffel' ;;
        purs) echo 'PureScript' ;;
        idr | ipkg) echo 'Idris' ;;
        agda) echo 'Agda' ;;
        lean) echo 'Lean' ;;
        v) echo 'Verilog / Coq / V' ;;
        sv | svh | vh) echo 'SystemVerilog / Verilog' ;;
        vhd | vhdl) echo 'VHDL' ;;
        tcl | tk) echo 'Tcl / Tk' ;;
        awk) echo 'AWK' ;;
        sed) echo 'Sed' ;;
        psm1 | psd1 | ps1xml) echo 'PowerShell' ;;
        ksh | csh | tcsh | dash) echo 'Shell Script' ;;
        au3) echo 'AutoIt' ;;
        ahk) echo 'AutoHotkey' ;;
        applescript | scpt) echo 'AppleScript' ;;
        coffee | litcoffee) echo 'CoffeeScript' ;;
        sol) echo 'Solidity' ;;
        vy) echo 'Vyper' ;;
        move) echo 'Move' ;;
        wat | wast) echo 'WebAssembly Text' ;;
        cu | cuh) echo 'CUDA' ;;
        clc) echo 'OpenCL' ;;
        glsl | vert | frag | geom | tesc | tese | comp | wgsl | hlsl | fx | metal | shader | cg | cginc) echo 'Shader' ;;
        gd | gdshader | tscn | tres | godot) echo 'Godot' ;;
        hx | hxml) echo 'Haxe' ;;
        as | mxml) echo 'ActionScript / MXML' ;;
        cr) echo 'Crystal' ;;
        nims | nimble) echo 'Nim' ;;
        vapi) echo 'Vala' ;;
        re | rei) echo 'Reason' ;;
        res | resi) echo 'ReScript' ;;
        raku | rakumod | rakutest | p6) echo 'Raku' ;;
        pro | p | prolog) echo 'Prolog / Project' ;;
        st | smalltalk) echo 'Smalltalk / Structured Text' ;;
        forth | fth | fs4) echo 'Forth' ;;
        bas | vbs | vba | frm | cls) echo 'BASIC / Visual Basic' ;;
        abap) echo 'ABAP' ;;
        cfc | cfm | cfml) echo 'ColdFusion' ;;
        rmd | rnw | rproj) echo 'R Project / Document' ;;
        sas) echo 'SAS' ;;
        do | ado | mata) echo 'Stata' ;;
        mat) echo 'MATLAB Data' ;;
        ipf) echo 'Igor Pro' ;;
        nb | wl | wls) echo 'Wolfram' ;;
        mo | mos) echo 'Modelica' ;;
        mps | gms) echo 'Optimization Model' ;;
        robot | resource) echo 'Robot Framework' ;;
        feature) echo 'Gherkin' ;;
        spec) echo 'Specification' ;;
        test | snap) echo 'Test / Snapshot' ;;
        bzl | bazel) echo 'Bazel' ;;
        nix) echo 'Nix' ;;
        tf | tfvars | hcl) echo 'Terraform / HCL' ;;
        tfstate) echo 'Terraform State' ;;
        cue) echo 'CUE' ;;
        dhall) echo 'Dhall' ;;
        json5 | jsonl | ndjson) echo 'JSON' ;;
        properties | prefs | cnf | config | rc | desktop | service | socket | timer | target | mount | path | rules | policy | reg | inf | plist | entitlements | manifest) echo 'Configuration' ;;
        xsd | xsl | xslt | dtd | wsdl | resx | xaml | axml | csproj | vbproj | fsproj | vcxproj | props | targets | iml) echo 'XML / Project' ;;
        sln | slnx | code-workspace | workspace | project | pbxproj | xcconfig) echo 'IDE Project' ;;
        editorconfig | gitignore | gitattributes | dockerignore | npmrc) echo 'Tool Config' ;;
        adoc | asciidoc | asc | rst | rest | tex | ltx | bib | sty | dtx | ins | org | wiki | mediawiki | textile | rdoc | pod | nfo | info | man | roff | rtf | text) echo 'Text / Documentation' ;;
        odt | ott | fodt | pages) echo 'Text Document' ;;
        ods | ots | fods | numbers) echo 'Spreadsheet' ;;
        odp | otp | fodp | key) echo 'Presentation' ;;
        epub | mobi | azw | azw3 | djvu | djv | fb2) echo 'E-book' ;;
        ps | eps | ai) echo 'PostScript / Vector' ;;
        svg | svgz) echo 'SVG' ;;
        png | jpg | jpeg | jpe | jfif | gif | webp | avif | heic | heif | bmp | dib | tif | tiff | ico | cur | icns | tga | psd | psb | xcf | kra | ora | exr | hdr | ppm | pgm | pbm | pnm | dds | ktx | ktx2) echo 'Image' ;;
        mp3 | wav | wave | flac | ogg | oga | opus | aac | m4a | wma | aiff | aif | alac | mid | midi | amr | au | caf | aifc) echo 'Audio' ;;
        mp4 | m4v | mkv | webm | avi | mov | qt | wmv | flv | mpg | mpeg | m2v | m2ts | vob | ogv | 3gp | 3g2) echo 'Video' ;;
        srt | vtt | ass | ssa | sub | sbv) echo 'Subtitle' ;;
        zip | zipx | rar | 7z | tar | gz | bz2 | xz | zst | zstd | lz | lzma | lz4 | br | tgz | tbz | tbz2 | txz | cab | arj | cpio | xar | sit | sitx) echo 'Archive' ;;
        iso | img | dmg | vhdx | vmdk | qcow | qcow2 | vdi | vfd) echo 'Disk Image' ;;
        deb | rpm | apk | aab | appx | msix | msi | pkg | flatpak | appimage | nupkg | whl | egg | gem | crate | vsix | crx | xpi) echo 'Package' ;;
        exe | dll | so | dylib | a | o | obj | lib | lo | la | class | jar | war | ear | pyc | pyo | pyd | beam | elc | com | bin | out | elf | dex) echo 'Binary / Compiled Code' ;;
        ttf | otf | woff | woff2 | eot | pfa | pfb) echo 'Font' ;;
        db | sqlite | sqlite3 | db3 | mdb | accdb | sqlitedb) echo 'Database' ;;
        parquet | arrow | feather | orc | avro | h5 | hdf5 | hdf | nc | npy | npz | pkl | pickle | rds | rdata) echo 'Data' ;;
        geojson | topojson | kml | kmz | gpx | shp | shx | dbf | prj | geotiff) echo 'GIS' ;;
        stl | fbx | blend | gltf | glb | dae | ply | 3ds | max | c4d | step | stp | iges | igs | dwg | dxf | skp | scad) echo '3D / CAD' ;;
        pem | crt | cer | der | p12 | pfx | p7b | p7c | csr | pub | gpg | pgp) echo 'Certificate / Key' ;;
        pcap | pcapng | cap | har) echo 'Network Capture' ;;
        torrent) echo 'BitTorrent' ;;
        bak | backup | old | orig | tmp | swp | swo) echo 'Backup / Temporary' ;;
        patch | diff) echo 'Patch' ;;
        map) echo 'Source Map' ;;
        sum | sha1 | sha256 | sha512 | md5) echo 'Checksum' ;;
        ics | ical | vcf) echo 'Calendar / Contact' ;;
        http) echo 'HTTP Request' ;;
        *) echo "Other" ;;
    esac
}

# Снимок списка до создания отчётов; NUL сохраняет пробелы и переводы строк в именах.
FILE_LIST=$(mktemp "${TMPDIR:-/tmp}/listing-project.XXXXXXXX") || exit 1
trap 'rm -f -- "$FILE_LIST"' EXIT
if ! find "$TARGET_DIR" -type f ! -path "$FILE_LIST" -print0 > "$FILE_LIST"; then exit 1; fi
if (( SAVE )); then
    printf '======== Листинг файлов ========\n' > "$LISTING_FILE" || exit 1
    : > "$STATS_FILE" || exit 1
    exec 3>>"$LISTING_FILE" || exit 1
fi

LANGS=(); COUNTS=(); SIZES=(); BUCKETS=(0 0 0 0 0 0)
TOTAL_FILES=0; TOTAL_SIZE=0
while IFS= read -r -d '' FILE; do
    # Старые отчёты и их жёсткие ссылки не должны попадать в новый отчёт.
    if (( SAVE )) && { [[ "$FILE" -ef "$STATS_FILE" ]] || [[ "$FILE" -ef "$LISTING_FILE" ]]; }; then continue; fi
    SIZE_BYTES=$(stat -c%s -- "$FILE" 2>/dev/null) ||
        SIZE_BYTES=$(stat -f%z -- "$FILE" 2>/dev/null) || {
            printf 'Не удалось прочитать размер: %s\n' "$FILE" >&2; continue;
        }
    LANG=$(detect_language "$FILE")
    index=0
    while (( index < ${#LANGS[@]} )) && [[ "${LANGS[$index]}" != "$LANG" ]]; do ((index+=1)); done
    LANGS[$index]="$LANG"
    COUNTS[$index]=$(( ${COUNTS[$index]:-0} + 1 ))
    SIZES[$index]=$(( ${SIZES[$index]:-0} + SIZE_BYTES ))
    if (( SIZE_BYTES == 0 )); then bucket=0
    elif (( SIZE_BYTES <= 5120 )); then bucket=1
    elif (( SIZE_BYTES <= 10240 )); then bucket=2
    elif (( SIZE_BYTES <= 51200 )); then bucket=3
    elif (( SIZE_BYTES <= 102400 )); then bucket=4
    else bucket=5; fi
    BUCKETS[$bucket]=$(( ${BUCKETS[$bucket]} + 1 ))
    ((TOTAL_FILES+=1)); ((TOTAL_SIZE+=SIZE_BYTES))
    if (( SAVE )); then
        printf '=====\n%s\n-----\n' "$FILE" >&3
        if [[ ! -s "$FILE" ]] || LC_ALL=C grep -Iq . "$FILE"; then
            cat -- "$FILE" >&3 || exit 1
        else
            printf '[Бинарный файл: содержимое пропущено]\n' >&3
        fi
        printf '\n\n' >&3
    fi
done < "$FILE_LIST"
if (( SAVE )); then exec 3>&-; fi

print_stats() {
    printf '\n======== Информация о проекте ========\nКаталог сканирования: %s\nВсего файлов: %d\nОбщий размер (в байтах): %d\n' "$TARGET_DIR" "$TOTAL_FILES" "$TOTAL_SIZE"
    LC_ALL=C awk -v size="$TOTAL_SIZE" 'BEGIN {printf "Общий размер (в KB): %.2f\n", size/1024}'
    printf '\n=== Статистика по языкам и форматам ===\n'
    printf '%s | %s | %s | %s | %s\n' 'Язык / формат' 'Файлов' '% от всех' 'Размер (KB)' '% объёма'
    for ((index=0; index<${#LANGS[@]}; index++)); do
        printf '%s | %d | ' "${LANGS[$index]}" "${COUNTS[$index]}"
        LC_ALL=C awk -v count="${COUNTS[$index]}" -v size="${SIZES[$index]}" -v total="$TOTAL_FILES" -v bytes="$TOTAL_SIZE" \
            'BEGIN {printf "%.2f%% | %.2f | %.2f%%\n", total ? 100*count/total : 0, size/1024, bytes ? 100*size/bytes : 0}'
    done
    printf '\n=== Распределение по размерам файлов ===\n'
    labels=('0 KB' '>0–5 KB' '>5–10 KB' '>10–50 KB' '>50–100 KB' '>100 KB')
    for ((index=0; index<6; index++)); do printf '%s | %d\n' "${labels[$index]}" "${BUCKETS[$index]}"; done
}
if (( SAVE )); then
    set -o pipefail
    print_stats | tee "$STATS_FILE" || exit 1
    printf '\nСтатистика сохранена в %s\nЛистинг сохранён в %s\n' "$STATS_FILE" "$LISTING_FILE"
else
    print_stats
fi
