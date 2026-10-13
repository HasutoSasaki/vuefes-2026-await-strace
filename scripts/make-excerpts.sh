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
  echo "## ① await Promise.resolve()  印A〜印Bの間"
  between "$OUT/01-marks-resolve.log" 'MARK A' 'MARK B' | clean | blocking_only
  echo
  echo "## ① await fetch()  印A〜印Bの間"
  between "$OUT/01-marks-fetch.log" 'MARK A' 'MARK B' | grep -E 'MARK|socket\(AF_INET|connect\(|epoll_pwait\(1[0-9], \[|write\(2[0-9]|read\(2[0-9]' | clean | blocking_only
} > "$LOGS/01-marks-resolve-vs-fetch.txt"

{
  echo "## ② A/B/C/D 所要時間（モック 300ms 固定遅延、各3回）"
  cat "$OUT/02-abcd-timing.txt"
} > "$LOGS/02-abcd-timing.txt"

{
  echo "## ② A 直列: connect と ブロックする epoll_pwait の並び"
  grep -E 'connect\(|epoll_pwait\(1[0-9], ' "$OUT/02-abcd-A.log" | clean | blocking_only
  echo
  echo "## ② C 先に2本: 同上"
  grep -E 'connect\(|epoll_pwait\(1[0-9], ' "$OUT/02-abcd-C.log" | clean | blocking_only
} > "$LOGS/02-strace-A-vs-C.txt"

{
  echo "## F: fetch() 直後に 1 秒ビジーループ → socket() すら出ない"
  grep -E 'socket\(AF_INET|connect\(|MARK' "$OUT/02-fire-F.log" | clean
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

# 生ログ
cp "$OUT"/01-marks-resolve.log "$LOGS/raw/trace_marks_resolve.log"
cp "$OUT"/01-marks-fetch.log   "$LOGS/raw/trace_marks_fetch.log"
cp "$OUT"/02-abcd-A.log        "$LOGS/raw/trace_A.log"
cp "$OUT"/02-abcd-C.log        "$LOGS/raw/trace_C.log"
cp "$OUT"/02-fire-F.log        "$LOGS/raw/trace_F.log"
cp "$OUT"/02-yield-G.log       "$LOGS/raw/trace_G.log"
cp "$OUT"/02-yield-H.log       "$LOGS/raw/trace_H.log"
[ -f "$OUT/03-nuxt-serial.log" ]   && cp "$OUT/03-nuxt-serial.log"   "$LOGS/raw/trace_nuxt_serial.log"
[ -f "$OUT/03-nuxt-parallel.log" ] && cp "$OUT/03-nuxt-parallel.log" "$LOGS/raw/trace_nuxt_parallel.log"

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
