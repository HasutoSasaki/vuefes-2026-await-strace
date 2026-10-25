#!/usr/bin/env bash
# Nuxt SSR の useFetch 直列 vs 束ねを strace で比較する
# ページごとに Nuxt を起動し直し、初回リクエスト（接続プールが空の状態）を記録する
set -uo pipefail
cd "$(dirname "$0")"
MOCK=${MOCK:-../mock.mjs}
OUT=${OUT:-.}
mkdir -p "$OUT"
PAGES=${PAGES:-serial parallel nowait}

node "$MOCK" > "$OUT/03-mock.log" 2>&1 & MOCK_PID=$!
sleep 1

for page in $PAGES; do
  PORT=3001 strace -f -tt -T -e trace=socket,connect,epoll_pwait,write,read \
    -o "$OUT/03-nuxt-${page}.log" node .output/server/index.mjs > "$OUT/03-nuxt-${page}-stdout.log" 2>&1 &
  STRACE_PID=$!
  sleep 3
  echo "== $page =="
  curl -s -o /dev/null -w "  cold  %{time_total}s\n" "http://127.0.0.1:3001/${page}"
  for i in 1 2 3; do
    curl -s -o /dev/null -w "  warm  %{time_total}s\n" "http://127.0.0.1:3001/${page}"
  done
  sleep 0.5
  # strace ではなく tracee の node を止める
  pkill -TERM -f '\.output/server/index\.mjs' || true
  wait $STRACE_PID 2>/dev/null || true
done

kill $MOCK_PID 2>/dev/null || true
wait 2>/dev/null || true
