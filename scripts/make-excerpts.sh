#!/usr/bin/env bash
# run-all.sh が出した生ログ（OUT/）から、スライド用の抜粋（LOGS/*.txt）と環境情報を生成する
# usage: scripts/make-excerpts.sh [OUT=out] [LOGS=logs]
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-out}
LOGS=${2:-logs}
mkdir -p "$LOGS/raw"

# 見やすくする: pid 列を落とし、sockaddr を短縮し、events 配列を [...] に、write/read のデータを先頭 20 文字に
clean() {
  grep -vE 'EAGAIN|AF_UNIX|AF_NETLINK|read\(1[0-9], |<unfinished \.\.\.>|resumed>' \
  | sed -E 's/^[0-9]+ +//; s/\{sa_family[^}]*\}, 16/127.0.0.1:3000/; s/\[\{events=[^]]*\]/[...]/; s/(write|read)\(([0-9]+), "([^"\\]{0,20})[^"]*"[^)]*\)/\1(\2, "\3...")/'
}
# timeout 0 の epoll_pwait（ブロックしない呼び出し）を落とす
blocking_only() { grep -vE ', 0, NULL, 8\) = [0-9]+( <|$)'; }
# 最初の s 行から最初の e 行までを抜く
between() { local f=$1 s=$2 e=$3 S E; S=$(grep -n "$s" "$f" | head -1 | cut -d: -f1); E=$(grep -n "$e" "$f" | head -1 | cut -d: -f1); [ -n "$S" ] && [ -n "$E" ] && sed -n "${S},${E}p" "$f"; }

{
  echo "## ① await Promise.resolve()  MARK A〜MARK B の間（モック遅延なし）"
  between "$OUT/01-marks-resolve.log" 'MARK A' 'MARK B' | clean | blocking_only
  echo
  echo "## ① await fetch()  MARK A〜MARK B の間（モック遅延なし）"
  between "$OUT/01-marks-fetch.log" 'MARK A' 'MARK B' | grep -E 'MARK|socket\(AF_INET|connect\(|epoll_pwait\(1[0-9], \[|write\(2[0-9]|read\(2[0-9]' | clean | blocking_only
} > "$LOGS/01-marks-resolve-vs-fetch.txt"

{
  echo "## ② A/B/C/D 所要時間（モック 300ms 固定遅延、各3回）"
  cat "$OUT/02-abcd-timing.txt"
} > "$LOGS/02-abcd-timing.txt"

{
  echo "## ② A 直列: socket / connect / write / ブロックする epoll_pwait / read の並び"
  grep -E 'socket\(AF_INET|connect\(|epoll_pwait\(1[0-9], |write\(2[0-9], "GET|read\(2[0-9], "HTTP' "$OUT/02-abcd-A.log" | clean | blocking_only
  echo
  echo "## ② B Promise.all: 同上"
  grep -E 'socket\(AF_INET|connect\(|epoll_pwait\(1[0-9], |write\(2[0-9], "GET|read\(2[0-9], "HTTP' "$OUT/02-abcd-B.log" | clean | blocking_only
  echo
  echo "## ② C 先に2本: 同上"
  grep -E 'socket\(AF_INET|connect\(|epoll_pwait\(1[0-9], |write\(2[0-9], "GET|read\(2[0-9], "HTTP' "$OUT/02-abcd-C.log" | clean | blocking_only
} > "$LOGS/02-strace-A-B-C.txt"

if [ -f "$OUT/02-abcd-B-full.log" ]; then
  {
    echo "## ② B を絞り込みなしで取ったときの epoll / io_uring まわり"
    echo "## epoll への登録（EPOLL_CTL_ADD / MOD）は libuv が io_uring_enter でまとめて送る。epoll_ctl の syscall は登録の削除（EPOLL_CTL_DEL）だけ"
    # 別スレッドの行に割り込まれて 2 行に分かれた呼び出しを 1 行につなげてから抜く。待たない epoll_pwait（timeout 0）は落とす
    awk -f scripts/merge-unfinished.awk "$OUT/02-abcd-B-full.log" | grep -E 'epoll_create1|epoll_ctl|io_uring_(setup|enter)|socket\(AF_INET|connect\(2|getsockopt\(2|epoll_pwait\(15, \[\{|write\(2[0-9], "GET|read\(2[0-9], "HTTP|close\(2[12]\)' | grep -vE ', 0, NULL, 8\) = [0-9]+' | sed -E 's/^[0-9]+ +//; s/\{sa_family[^}]*\}, 16/127.0.0.1:3000/; s/io_uring_setup\(256, \{[^)]*\)/io_uring_setup(256, {...})/; s/(write|read)\(([0-9]+), "([^"\\]{0,20})[^"]*"[^)]*\)/\1(\2, "\3...")/'
    echo
    echo "## システムコールの回数（strace -c）"
    grep -E 'calls|epoll|io_uring|total' "$OUT/02-abcd-B-count.txt"
  } > "$LOGS/02-epoll-registration-B.txt"
fi

{
  echo "## F: fetch() 直後に 1 秒ビジーループ → socket() すら出ない"
  grep -E 'socket\(AF_INET|connect\(|MARK' "$OUT/02-fire-F.log" | clean
  echo
  echo "## F2: C と同じく 2 本呼んでから 1 秒ビジーループ → ループ後に socket() と connect() が 2 本まとめて出る"
  grep -E 'socket\(AF_INET|connect\(|MARK|epoll_pwait\(1[0-9], ' "$OUT/02-fire-F2.log" | clean | blocking_only
  echo
  echo "## F3: B と同じく Promise.all で 2 本束ねてから 1 秒ビジーループ → ループ後に socket() と connect() が 2 本まとめて出る"
  grep -E 'socket\(AF_INET|connect\(|MARK|epoll_pwait\(1[0-9], ' "$OUT/02-fire-F3.log" | clean | blocking_only
  echo
  echo "## G: fetch() → await Promise.resolve() → 500ms ビジー（マイクロタスクではイベントループに戻らない）"
  grep -E 'connect\(|MARK|epoll_pwait\(1[0-9], ' "$OUT/02-yield-G.log" | clean | blocking_only
  echo
  echo "## H: fetch() → await setTimeout(0) → 500ms ビジー（イベントループに戻ると connect が出る）"
  grep -E 'connect\(|MARK|epoll_pwait\(1[0-9], ' "$OUT/02-yield-H.log" | clean | blocking_only
} > "$LOGS/02-when-does-connect-happen.txt"

if [ -f "$OUT/03-nuxt-serial.log" ]; then
  {
    echo "## ③ Nuxt SSR  useFetch 直列 vs Promise.all（curl time_total、ページごとに Nuxt 再起動）"
    cat "$OUT/03-nuxt-timing.txt"
  } > "$LOGS/03-nuxt-timing.txt"
  {
    echo "## ③ Nuxt serial.vue  await useFetch(a); await useFetch(b)  初回リクエスト"
    between "$OUT/03-nuxt-serial.log" 'MARK serial start' 'MARK serial end' | grep -E 'MARK|socket\(AF_INET|connect\(|epoll_pwait|write\(2[0-9]|read\(2[0-9]' | clean | blocking_only
    echo
    echo "## ③ Nuxt parallel.vue  Promise.all([useFetch(a), useFetch(b)])  初回リクエスト"
    between "$OUT/03-nuxt-parallel.log" 'MARK parallel start' 'MARK parallel end' | grep -E 'MARK|socket\(AF_INET|connect\(|epoll_pwait|write\(2[0-9]|read\(2[0-9]' | clean | blocking_only
  } > "$LOGS/03-nuxt-serial-vs-parallel.txt"
fi
if [ -f "$OUT/03-nuxt-nowait.log" ]; then
  {
    echo "## ③ Nuxt nowait.vue  useFetch(a); useFetch(b)（await なし）  初回リクエスト"
    # await しないので MARK end の後に通信が出る。2 本目の応答を読むところまでを抜く
    awk '/MARK nowait start/{f=1} f{print} f&&/read\(2[0-9], "HTTP/{n++} n==2{exit}' "$OUT/03-nuxt-nowait.log" | grep -E 'MARK|socket\(AF_INET|connect\(|epoll_pwait|write\(2[0-9]|read\(2[0-9]' | clean | blocking_only
  } > "$LOGS/03-nuxt-nowait.txt"
fi

# 生ログ
cp "$OUT"/01-marks-resolve.log "$LOGS/raw/trace_marks_resolve.log"
cp "$OUT"/01-marks-fetch.log   "$LOGS/raw/trace_marks_fetch.log"
cp "$OUT"/02-abcd-A.log        "$LOGS/raw/trace_A.log"
cp "$OUT"/02-abcd-B.log        "$LOGS/raw/trace_B.log"
cp "$OUT"/02-abcd-C.log        "$LOGS/raw/trace_C.log"
[ -f "$OUT/02-abcd-B-full.log" ] && cp "$OUT/02-abcd-B-full.log" "$LOGS/raw/trace_B_full.log"
[ -f "$OUT/02-abcd-B-count.txt" ] && cp "$OUT/02-abcd-B-count.txt" "$LOGS/raw/count_B.txt"
cp "$OUT"/02-fire-F.log        "$LOGS/raw/trace_F.log"
cp "$OUT"/02-fire-F2.log       "$LOGS/raw/trace_F2.log"
cp "$OUT"/02-fire-F3.log       "$LOGS/raw/trace_F3.log"
cp "$OUT"/02-yield-G.log       "$LOGS/raw/trace_G.log"
cp "$OUT"/02-yield-H.log       "$LOGS/raw/trace_H.log"
[ -f "$OUT/03-nuxt-serial.log" ]   && cp "$OUT/03-nuxt-serial.log"   "$LOGS/raw/trace_nuxt_serial.log"
[ -f "$OUT/03-nuxt-parallel.log" ] && cp "$OUT/03-nuxt-parallel.log" "$LOGS/raw/trace_nuxt_parallel.log"
[ -f "$OUT/03-nuxt-nowait.log" ]   && cp "$OUT/03-nuxt-nowait.log"   "$LOGS/raw/trace_nuxt_nowait.log"

# 取得環境
{
  echo "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "kernel: $(uname -srm)"
  echo "os:     $(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "node:   $(node -v)"
  echo "strace: $(strace -V | head -1)"
  echo "glibc:  $(ldd --version | head -1)"
  echo "nuxt:   $(node -p "try{require('./experiments/nuxt/node_modules/nuxt/package.json').version}catch{'(not installed)'}")"
  echo "docker: ${IN_DOCKER:-unknown}"
} > "$LOGS/ENV.txt"

echo "excerpts written to $LOGS/"
