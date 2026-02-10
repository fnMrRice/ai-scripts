#!/bin/bash
# 输入一个目录或者压缩包，重新打包成另一个格式的压缩包
# 输入目录时，支持使用参数控制是否递归从子目录中查找压缩文件，支持参数控制递归深度
# 当压缩包中也包含压缩包时，支持使用参数控制是否递归重新打包
# 支持各种常见压缩格式

set -e

show_help() {
    echo "用法: $0 [选项] <输入路径> <输出格式>"
    echo "选项:"
    echo "  -r           递归查找子目录中的压缩包"
    echo "  -d <深度>    递归深度 (默认: 无限)"
    echo "  -a           递归重新打包压缩包内的压缩包"
    echo "  -y           跳过每个压缩包处理前的确认"
    echo "  -h           显示帮助"
    echo "支持的压缩格式: zip, tar, tar.gz, tar.bz2, tar.xz, 7z, rar"
}

# 默认参数
RECURSIVE=0
MAX_DEPTH=""
REPACK_INNER=0
SKIP_CONFIRM=0

# 解析参数
while getopts "rd:ahy" opt; do
    case $opt in
        r) RECURSIVE=1 ;;
        d) MAX_DEPTH=$OPTARG ;;
        a) REPACK_INNER=1 ;;
        y) SKIP_CONFIRM=1 ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done
shift $((OPTIND-1))

if [ $# -lt 2 ]; then
    show_help
    exit 1
fi

INPUT_PATH="$1"
OUTPUT_FORMAT="$2"

SUPPORTED_FORMATS="zip tar tar.gz tgz tar.bz2 tbz2 tar.xz txz 7z rar"

get_ext() {
    fname="$1"
    case "$fname" in
        *.tar.gz|*.tgz) echo "tar.gz" ;;
        *.tar.bz2|*.tbz2) echo "tar.bz2" ;;
        *.tar.xz|*.txz) echo "tar.xz" ;;
        *.zip) echo "zip" ;;
        *.tar) echo "tar" ;;
        *.7z) echo "7z" ;;
        *.rar) echo "rar" ;;
        *) echo "" ;;
    esac
}

log() {
    echo "[`date '+%Y-%m-%d %H:%M:%S'`] $@"
}

extract_archive() {
    archive="$1"
    dest="$2"
    ext=$(get_ext "$archive")
    log "解压: $archive 到 $dest (格式: $ext)"
    mkdir -p "$dest"
    local err=0
    case "$ext" in
        zip) unzip -q "$archive" -d "$dest" || err=1 ;;
        tar) tar -xf "$archive" -C "$dest" || err=1 ;;
        tar.gz) tar -xzf "$archive" -C "$dest" || err=1 ;;
        tar.bz2) tar -xjf "$archive" -C "$dest" || err=1 ;;
        tar.xz) tar -xJf "$archive" -C "$dest" || err=1 ;;
        7z) 7z x -o"$dest" "$archive" >/dev/null || err=1 ;;
        rar) unrar x -o+ "$archive" "$dest" >/dev/null || err=1 ;;
        *) log "不支持的压缩格式: $archive"; exit 2 ;;
    esac
    if [ $err -ne 0 ]; then
        log "解压失败: $archive"
        while true; do
            read -p "是否继续处理下一个压缩包？[y/N] " ans
            case "$ans" in
                y|Y) return 1 ;;
                n|N|"") exit 3 ;;
                *) ;;
            esac
        done
    fi
}

create_archive() {
    src="$1"
    out="$2"
    fmt="$3"
    log "打包: $src -> $out (格式: $fmt)"
    case "$fmt" in
        zip) (cd "$src" && zip -qr "$out" .) ;; # 不加-j，保留目录结构和权限
        tar) tar --preserve-permissions -cf "$out" -C "$src" . ;;
        tar.gz) tar --preserve-permissions -czf "$out" -C "$src" . ;;
        tar.bz2) tar --preserve-permissions -cjf "$out" -C "$src" . ;;
        tar.xz) tar --preserve-permissions -cJf "$out" -C "$src" . ;;
        7z) 7z a -sdel -mhe=on "$out" "$src"/* >/dev/null ;; # 7z/rar本身保留权限有限
        rar) rar a -ep1 "$out" "$src"/* >/dev/null ;;
        *) log "不支持的输出格式: $fmt"; exit 2 ;;
    esac
}

find_archives() {
    dir="$1"
    depth_opt=""
    if [ -n "$MAX_DEPTH" ]; then
        depth_opt="-maxdepth $MAX_DEPTH"
    fi
    log "查找压缩包: $dir $depth_opt"
    find "$dir" $depth_opt -type f \( \
        -iname "*.zip" -o -iname "*.tar" -o -iname "*.tar.gz" -o -iname "*.tgz" \
        -o -iname "*.tar.bz2" -o -iname "*.tbz2" -o -iname "*.tar.xz" -o -iname "*.txz" \
        -o -iname "*.7z" -o -iname "*.rar" \
    \)
}

confirm_process() {
    archive="$1"
    level="${2:-0}"
    indent=$(printf '%*s' $((level*2)) '')
    log "${indent}即将处理压缩包 (层级$level): $archive"
    log "${indent}文件大小: $(stat -c %s "$archive") 字节"
    log "${indent}修改时间: $(stat -c %y "$archive")"
    log "${indent}文件类型: $(file -b "$archive")"
    # 检查压缩包内是否包含压缩包
    tmpinfo=$(mktemp -d)
    ext=$(get_ext "$archive")
    case "$ext" in
        zip) unzip -l "$archive" | grep -Ei '\.(zip|tar|gz|bz2|xz|7z|rar)$' >/dev/null ;;
        tar|tar.gz|tar.bz2|tar.xz)
            tar -tf "$archive" | grep -Ei '\.(zip|tar|gz|bz2|xz|7z|rar)$' >/dev/null ;;
        7z) 7z l "$archive" | grep -Ei '\.(zip|tar|gz|bz2|xz|7z|rar)$' >/dev/null ;;
        rar) unrar lb "$archive" | grep -Ei '\.(zip|tar|gz|bz2|xz|7z|rar)$' >/dev/null ;;
        *) ;;
    esac
    if [ $? -eq 0 ]; then
        log "${indent}压缩包内包含其他压缩包"
    else
        log "${indent}压缩包内不包含其他压缩包"
    fi
    rm -rf "$tmpinfo"
    echo "${indent}----------------------------------------"
    read -p "${indent}是否处理该压缩包？[y/N] " ans
    case "$ans" in
        y|Y) return 0 ;;
        *) log "${indent}跳过: $archive"; return 1 ;;
    esac
}

process_archive() {
    archive="$1"
    out_fmt="$2"
    level="${3:-0}"
    # 修正多后缀情况
    ext=$(get_ext "$archive")
    base="$archive"
    case "$ext" in
        tar.gz) base="${archive%.tar.gz}"; base="${base%.tgz}" ;;
        tar.bz2) base="${archive%.tar.bz2}"; base="${base%.tbz2}" ;;
        tar.xz) base="${archive%.tar.xz}"; base="${base%.txz}" ;;
        zip) base="${archive%.zip}" ;;
        tar) base="${archive%.tar}" ;;
        7z) base="${archive%.7z}" ;;
        rar) base="${archive%.rar}" ;;
        *) base="${archive%.*}" ;;
    esac
    tmpdir=$(mktemp -d)
    # 确认处理
    if [ "$SKIP_CONFIRM" != "1" ]; then
        confirm_process "$archive" "$level" || { rm -rf "$tmpdir"; return; }
    fi
    indent=$(printf '%*s' $((level*2)) '')
    log "${indent}处理压缩包 (层级$level): $archive"
    extract_archive "$archive" "$tmpdir" || { rm -rf "$tmpdir"; return; }
    if [ "$REPACK_INNER" = "1" ]; then
        # 递归处理内部压缩包
        for inner in $(find_archives "$tmpdir"); do
            log "${indent}递归处理内部压缩包: $inner"
            process_archive "$inner" "$out_fmt" $((level+1))
        done
    fi
    out_file="${base}.${out_fmt}"
    create_archive "$tmpdir" "$out_file" "$out_fmt"
    rm -rf "$tmpdir"
    log "${indent}已重新打包: $archive -> $out_file"
}

process_dir() {
    dir="$1"
    out_fmt="$2"
    log "处理目录: $dir"
    # 支持 . 作为当前目录
    if [ "$dir" = "." ]; then
        dir="$(pwd)"
    fi
    for archive in $(find_archives "$dir"); do
        process_archive "$archive" "$out_fmt"
    done
}

main() {
    log "开始处理: 输入路径=$INPUT_PATH, 输出格式=$OUTPUT_FORMAT"
    if [ -f "$INPUT_PATH" ]; then
        process_archive "$INPUT_PATH" "$OUTPUT_FORMAT"
    elif [ -d "$INPUT_PATH" ]; then
        # 支持 . 作为当前目录
        if [ "$INPUT_PATH" = "." ]; then
            INPUT_PATH="$(pwd)"
        fi
        if [ "$RECURSIVE" = "1" ]; then
            process_dir "$INPUT_PATH" "$OUTPUT_FORMAT"
        else
            log "仅处理当前目录: $INPUT_PATH"
            for archive in "$INPUT_PATH"/*; do
                [ -f "$archive" ] && process_archive "$archive" "$OUTPUT_FORMAT"
            done
        fi
    else
        log "输入路径无效: $INPUT_PATH"
        exit 1
    fi
}

main

