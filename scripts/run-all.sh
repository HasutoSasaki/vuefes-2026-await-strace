#!/usr/bin/env bash
# すべての実験を実行し、strace ログを out/ に出力する
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=${OUT:-out}
mkdir -p "$OUT"
TRACE="strace -f -tt -T -e trace=socket,connect,epoll_pwait,write,read"

# ① は遅延なしのモックで取る（遅延の有無に関係なく epoll_pwait が出ることを見るため）
DELAY_MS=0 node experiments/mock.mjs > "$OUT/mock-nodelay.log" 2>&1 & MOCK_PID=$!
sleep 1

echo "## ① await Promise.resolve() vs await fetch()（モック遅延なし）"
for m in resolve fetch; do
  $TRACE -o "$OUT/01-marks-$m.log" node experiments/marks.mjs "$m" > /dev/null
  echo "  wrote $OUT/01-marks-$m.log"
done

kill $MOCK_PID 2>/dev/null; wait $MOCK_PID 2>/dev/null || true

# ② 以降は 300ms 遅延のモックで取る（応答に時間がかかる API の代わり）
node experiments/mock.mjs > "$OUT/mock.log" 2>&1 & MOCK_PID=$!
sleep 1

echo "## ② A/B/C/D 所要時間"
for m in A B C D; do
  for i in 1 2 3; do node experiments/abcd.mjs "$m"; done
done | tee "$OUT/02-abcd-timing.txt"

echo "## ② A/B/C の strace"
for m in A B C; do
  $TRACE -o "$OUT/02-abcd-$m.log" node experiments/abcd.mjs "$m" > /dev/null
  echo "  wrote $OUT/02-abcd-$m.log"
done

echo "## ② B を絞り込みなしで（epoll への登録が io_uring で行われていることの確認）"
strace -f -c -o "$OUT/02-abcd-B-count.txt" node experiments/abcd.mjs B > /dev/null
strace -f -tt -T -o "$OUT/02-abcd-B-full.log" node experiments/abcd.mjs B > /dev/null

echo "## F/G/H 予約はいつ OS に届くか"
$TRACE -o "$OUT/02-fire-F.log" node experiments/fire.mjs F
$TRACE -o "$OUT/02-fire-F2.log" node experiments/fire.mjs F2
$TRACE -o "$OUT/02-fire-F3.log" node experiments/fire.mjs F3
for m in G H; do
  $TRACE -o "$OUT/02-yield-$m.log" node experiments/yield.mjs "$m"
done

kill $MOCK_PID 2>/dev/null; wait $MOCK_PID 2>/dev/null || true

echo "## ③ Nuxt SSR useFetch 直列 vs Promise.all"
if [ -d experiments/nuxt/.output ]; then
  (cd experiments/nuxt && OUT="../../$OUT" ./run.sh) | tee "$OUT/03-nuxt-timing.txt"
else
  echo "  skip: experiments/nuxt/.output がありません（cd experiments/nuxt && npm ci && npx nuxt build）"
fi

bash scripts/make-excerpts.sh "$OUT" "$OUT/excerpts"
echo "done. raw logs in $OUT/, excerpts in $OUT/excerpts/ (cp -r $OUT/excerpts/* logs/ で差し替え)"
