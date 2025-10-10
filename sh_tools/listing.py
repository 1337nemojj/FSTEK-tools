import os
import concurrent.futures
from tqdm import tqdm

def detect_language_by_extension(filename: str) -> str:
    _, ext = os.path.splitext(filename.lower())
    ext = ext.lstrip('.')  

    extension_map = {
        # Programming Languages
        'py': 'Python',
        'ipynb': 'Jupyter Notebook',
        'js': 'JavaScript',
        'jsx': 'JavaScript (JSX)',
        'ts': 'TypeScript',
        'tsx': 'TypeScript (TSX)',
        'java': 'Java',
        'kt': 'Kotlin',
        'kts': 'Kotlin Script',
        'scala': 'Scala',
        'groovy': 'Groovy',
        'go': 'GOLANG',
        'rs': 'Rust',
        'c': 'C',
        'h': 'C_C++ Header',
        'cpp': 'C++',
        'cc': 'C++',
        'cxx': 'C++',
        'hpp': 'C++ Header',
        'hxx': 'C++ Header',
        'hh': 'C++ Header',
        'cs': 'C#',
        'vb': 'Visual Basic .NET',
        'swift': 'Swift',
        'm': 'Objective-C',
        'mm': 'Objective-C++',
        'php': 'PHP',
        'dart': 'Dart',
        'rb': 'Ruby',
        'pl': 'Perl',
        'pm': 'Perl Module',
        'r': 'R',
        'lua': 'Lua',
        'ex': 'Elixir',
        'exs': 'Elixir',
        'erl': 'Erlang',
        'hrl': 'Erlang Header',
        'clj': 'Clojure',
        'cljs': 'ClojureScript',
        'lisp': 'Lisp',
        'el': 'Emacs Lisp',
        'nim': 'Nim',
        'zig': 'Zig',
        'asm': 'Assembly',
        's': 'Assembly',
        'S': 'Assembly',
        'vala': 'Vala',
        'wasm': 'WebAssembly',
    
        # Web / Markup / Styling
        'html': 'HTML',
        'htm': 'HTML',
        'css': 'CSS',
        'scss': 'SCSS',
        'sass': 'SASS',
        'less': 'LESS',
        'xml': 'XML',
        'json': 'JSON',
        'jsonc': 'JSON with Comments',
        'yaml': 'YAML',
        'yml': 'YAML',
    
        # Markdown / Text
        'md': 'Markdown',
        'markdown': 'Markdown',
        'txt': 'Plain Text',
        'rst': 'reStructuredText',
        'adoc': 'AsciiDoc',
    
        # Shell / Scripting
        'sh': 'Shell Script',
        'bash': 'Bash Script',
        'zsh': 'Zsh Script',
        'fish': 'Fish Script',
        'bat': 'Batch File',
        'cmd': 'Batch File',
        'ps1': 'PowerShell',
    
        # Config / Build
        'env': '.env File',
        'ini': 'INI Config',
        'cfg': 'Config File',
        'conf': 'Config File',
        'toml': 'TOML',
        'lock': 'Lock File',
        'yarn.lock': 'Yarn Lock',
        'package-lock.json': 'NPM Lock',
        'tsconfig.json': 'TypeScript Config',
        'package.json': 'NPM Package Config',
        'pyproject.toml': 'Python Project Config',
        'requirements.txt': 'Python Requirements',
        'setup.py': 'Python Setup',
        'make': 'Makefile',
        'mk': 'Makefile',
        'cmake': 'CMake',
        'gradle': 'Gradle',
        'build.gradle': 'Gradle Build Script',
        'pom.xml': 'Maven Config',
        'dockerfile': 'Dockerfile',
        'docker': 'Dockerfile',
    
        # Data / Logs
        'csv': 'CSV',
        'tsv': 'TSV',
        'log': 'Log File',
    
        # Docs / Office
        'pdf': 'PDF',
        'doc': 'Word Document',
        'docx': 'Word Document',
        'xls': 'Excel Spreadsheet',
        'xlsx': 'Excel Spreadsheet',
        'ppt': 'PowerPoint',
        'pptx': 'PowerPoint',
    
        # SQL / Database
        'sql': 'SQL',
        'db': 'Database File',
        'sqlite': 'SQLite Database',
    
        # Default
        '*': 'Other'
    }

    return extension_map.get(ext, 'Other')

def get_size_category(size_kb: float) -> str:
    if size_kb == 0:
        return '0 KB'
    elif 0 < size_kb <= 5:
        return '1–5 KB'
    elif 5 < size_kb <= 10:
        return '6–10 KB'
    elif 10 < size_kb <= 50:
        return '11–50 KB'
    elif 50 < size_kb <= 100:
        return '51–100 KB'
    else:
        return '>100 KB'

def process_file(index, file_path):
    language = 'Other'
    try:
        size_bytes = os.path.getsize(file_path)
        size_kb = size_bytes / 1024
        language = detect_language_by_extension(file_path)
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return index, {'language': language, 'size_kb': 0}, f"<Error reading file: {e}>"

    return index, {'language': language, 'size_kb': size_kb}, content

def generate_listing_and_stats(root_dir, output_stats_file, output_listing_file):
    all_files = []
    for foldername, _, filenames in os.walk(root_dir):
        for filename in filenames:
            file_path = os.path.join(foldername, filename)
            all_files.append(file_path)

    total_files = len(all_files)
    if total_files == 0:
        print(f"В каталоге '{root_dir}' не найдено файлов для сканирования.")
        return
    
    results = [None] * total_files
    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures_map = {executor.submit(process_file, i, path): i for i, path in enumerate(all_files)}
        for future in tqdm(concurrent.futures.as_completed(futures_map), total=len(futures_map), desc="Сканирование"):
            i, stats, content = future.result()
            results[i] = (all_files[i], stats, content)
    
    language_stats = {}
    size_distribution = {}
    total_size_bytes = 0

    for _, stats, _ in results:
        lang = stats['language']
        size_kb = stats['size_kb']
        total_size_bytes += size_kb * 1024

        if lang not in language_stats:
            language_stats[lang] = {'count': 0, 'size': 0.0}
        language_stats[lang]['count'] += 1
        language_stats[lang]['size'] += size_kb

        category = get_size_category(size_kb)
        size_distribution[category] = size_distribution.get(category, 0) + 1

    total_size_kb = total_size_bytes / 1024 if total_size_bytes else 0

    # === Запись общей статистики ===
    with open(output_stats_file, 'w', encoding='utf-8') as stats_out:
        stats_out.write("======== Информация о проекте ========\n\n")
        stats_out.write(f"Каталог сканирования: {root_dir}\n")
        stats_out.write(f"Всего файлов: {total_files}\n")
        stats_out.write(f"Общий размер (в байтах): {int(total_size_bytes)}\n")
        stats_out.write(f"Общий размер (в KB): {total_size_kb:.2f}\n\n")

        print("\n===== Итоговая статистика =====")
        print(f"Каталог сканирования: {root_dir}")
        print(f"Всего файлов: {total_files}")
        print(f"Общий размер (в KB): {total_size_kb:.2f}")

        stats_out.write("=== Статистика по языкам ===\n")
        stats_out.write("Язык | Файлов | % от общего | Общий размер (KB) | % от объёма\n")
        stats_out.write("-" * 79 + "\n")

        print("\n=== Статистика по языкам ===")
        langs_sorted = sorted(language_stats.items(), key=lambda x: x[1]['size'], reverse=True)
        for lang, data in langs_sorted:
            count, size_kb_sum = data['count'], data['size']
            count_percent = (count / total_files) * 100 if total_files else 0
            size_percent = (size_kb_sum / total_size_kb) * 100 if total_size_kb else 0

            line = (
                f"{lang:20s} | {count:6d} | {count_percent:10.2f}% "
                f"| {size_kb_sum:15.2f} | {size_percent:12.2f}%\n"
            )
            stats_out.write(line)
            print(line, end='')

    # === Запись листинга файлов ===
    with open(output_listing_file, 'w', encoding='utf-8') as listing_out:
        listing_out.write("======== Листинг файлов ========\n\n")
        for (file_path, _, content) in results:
            listing_out.write("=====" * 20 + "\n")
            listing_out.write(f"{file_path}\n")
            listing_out.write("-----" * 20 + "\n")
            listing_out.write(content + "\n")

    # === Новый функционал: выбор языка и формирование списка ===
    print("\n=== Найденные языки ===")
    langs = [lang for lang in language_stats.keys()]
    for i, lang in enumerate(langs, start=1):
        print(f"{i}) {lang} ({language_stats[lang]['count']} файлов, {language_stats[lang]['size']:.2f} KB)")

    selected = input("\nВведите номера языков через запятую (или Enter для пропуска): ").strip()
    if selected:
        try:
            indices = [int(x.strip()) for x in selected.split(',') if x.strip().isdigit()]
            chosen_langs = [langs[i - 1] for i in indices if 1 <= i <= len(langs)]
            for lang in chosen_langs:
                output_lang_file = f"Файлы_{lang.replace(' ', '_')}.txt"
                with open(output_lang_file, 'w', encoding='utf-8') as out_lang:
                    out_lang.write(f"=== Файлы языка: {lang} ===\n\n")
                    for path, st, _ in results:
                        if st['language'] == lang:
                            out_lang.write(f"{path} | {st['size_kb']:.2f} KB\n")
                print(f"Создан файл: {output_lang_file}")
        except Exception as e:
            print(f"Ошибка при выборе языков: {e}")

    print(f"\nСтатистика сохранена в '{output_stats_file}'")
    print(f"Листинг сохранён в '{output_listing_file}'")

def main():
    current_dir = os.getcwd()
    subdirs = [d for d in os.listdir(current_dir) if os.path.isdir(d)]
    subdirs.sort()

    print("Выберите, что сканировать:")
    print("0) Вся текущая директория (рекурсивно)")
    for idx, d in enumerate(subdirs, start=1):
        print(f"{idx}) {d}")

    choice = input("Введите номер пункта: ").strip()

    if choice == '0':
        target_dir = current_dir
    else:
        try:
            idx_choice = int(choice)
            if 1 <= idx_choice <= len(subdirs):
                target_dir = os.path.join(current_dir, subdirs[idx_choice - 1])
            else:
                print("Неверный выбор. Выходим.")
                return
        except ValueError:
            print("Неверный ввод. Выходим.")
            return

    generate_listing_and_stats(
        root_dir=target_dir,
        output_stats_file="Общая информация",
        output_listing_file="Описание программы. Приложение А"
    )

if __name__ == "__main__":
    main()



