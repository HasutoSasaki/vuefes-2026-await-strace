# あなたの await、OS まで届いてる？ — strace で覗く JavaScript の非同期

Vue Fes Japan 2026（2026-10-24）LT の検証一式です。Node.js の `await` が OS にどう届いているかを `strace` で観察します。

- スライド: （公開後に追記）
- 関連記事（DevelopersIO）
  - [Node.js の非同期処理をシステムコールから覗く](https://dev.classmethod.jp/articles/nodejs-async-deep-dive-with-syscalls/)
  - [Node.js の fetch を strace で追う](https://dev.classmethod.jp/articles/nodejs-fetch-strace/)
  - [複数 fetch の直列 vs Promise.all を strace で比べる](https://dev.classmethod.jp/articles/nodejs-multiple-fetch-strace/)
  - [JavaScriptの非同期処理はepollで成り立っているのか、Node.js、Deno、Bunそれぞれで覗いてみた](https://dev.classmethod.jp/articles/hasuto-js-async-epoll-node-deno-bun/)

## 3 つの問い

| # | 問い | 答え | ログ |
|---|---|---|---|
| 1 | await した時に、OS には何が届く？ | await だけでは何も届かない。fetch なら socket() や connect() が届く | [logs/01](logs/01-marks-resolve-vs-fetch.txt) |
| 2 | 直列と Promise.all、OS から見ると何が違う？ | 直列は 1 本届けて I/O 待ち。束ねると全部届けてから I/O 待ち | [logs/02](logs/02-strace-A-B-C.txt) |
| 3 | Nuxt の useFetch に置き換えると？ | 同じ形になる。await を並べると A（直列）、Promise.all で束ねると B と同じ | [logs/03](logs/03-nuxt-serial-vs-parallel.txt) |

## 実験

モックサーバー（`experiments/mock.mjs`）は `127.0.0.1:3000` で `/a` `/b` に応答します。① は遅延なし（`DELAY_MS=0`）、② と ③ は 300ms の固定遅延で動かします（応答に時間がかかる API の代わり）。

| ファイル | 内容 |
|---|---|
| `experiments/marks.mjs` | ① `process.stdout.write` の印で挟み、`await Promise.resolve()` と `await fetch()` の間に出るシステムコールを比べる |
| `experiments/abcd.mjs` | ② A 直列 / B `Promise.all` / C 先に 2 本呼んで個別 await / D 1 本 await 後に `Promise.all` の所要時間 |
| `experiments/fire.mjs` | F: `fetch()` 直後に 1 秒ビジーループ。その間 `socket()` が出ないことを見る / F2: C と同じく 2 本呼んでから 1 秒ビジーループ / F3: B と同じく `Promise.all` で 2 本束ねてから 1 秒ビジーループ。どちらもループ後に `socket()` と `connect()` が 2 本まとめて出ることを見る |
| `experiments/yield.mjs` | G: `await Promise.resolve()` ではイベントループに戻らない / H: `await setTimeout(0)` では戻って `connect` が出る |
| `experiments/nuxt/` | ③ Nuxt 4 SSR で `await useFetch` 直列（serial.vue）・`Promise.all`（parallel.vue）・await なし（nowait.vue）を比べる最小アプリ |

### 結果（Docker: node:22-bookworm = Node 22.23.3 / Nuxt 4.6.1 / strace 6.1、aarch64。詳細は `logs/ENV.txt`）

② 所要時間

| パターン | 所要時間 |
|---|---|
| A `await fetch; await fetch` | 632〜651 ms |
| B `Promise.all([fetch, fetch])` | 326〜337 ms |
| C 先に 2 本呼んで個別 await | 331〜334 ms |
| D 1 本 await してから `Promise.all([fetch])` | 642〜644 ms |

③ Nuxt SSR（初回リクエスト）

| ページ | cold | warm |
|---|---|---|
| `await useFetch(a); await useFetch(b)` | 748 ms | 633 ms |
| `Promise.all([useFetch(a), useFetch(b)])` | 436 ms | 323〜328 ms |
| `useFetch(a); useFetch(b)`（await なし） | 471 ms | 317〜335 ms |

strace の抜粋は `logs/*.txt`、生ログは `logs/raw/`、取得環境は `logs/ENV.txt` にあります。

> **`logs/` の出どころ**: 標準の `Dockerfile` でビルドしたコンテナ（node:22-bookworm、strace は apt の 6.1、macOS の Colima 上の aarch64）で `scripts/run-all.sh` を実行し、`out/excerpts/` をそのままコピーしたものです。手作業の整形はしていません。パターン B の strace（`logs/raw/trace_B.log`）と Nuxt の nowait.vue（`logs/raw/trace_nuxt_nowait.log`、`logs/03-nuxt-nowait.txt`）だけは、同じイメージで後から追加で取得しました。① の strace（`logs/01-marks-resolve-vs-fetch.txt`、`logs/raw/trace_marks_*.log`）は、モックを遅延なしにして 2026-10-19 に同じイメージで取り直しました。F2 と F3（`logs/raw/trace_F2.log`、`logs/raw/trace_F3.log`）も同じ日に追加で取得しました。絞り込みなしの B（`logs/raw/trace_B_full.log`、`logs/raw/count_B.txt`、`logs/02-epoll-registration-B.txt`）は 2026-10-20 に取得しました（`logs/ENV.txt` の date は最後に取得した時刻）。`docker compose up --build` を実行すると同じ形式で再生成されます。

## 動かし方

### Docker（推奨。strace に `SYS_PTRACE` が必要）

```bash
docker compose up --build
# 生ログは ./out/、スライド用の抜粋は ./out/excerpts/ に出ます
cp -r out/excerpts/* logs/   # logs/ を取り直したログで差し替える
```

Docker Hub の匿名プルがレート制限（429）に当たる場合は、同じダイジェストの公式イメージを別のミラーから取ってタグ付けしてください。

```bash
docker pull mirror.gcr.io/library/node:22-bookworm
docker tag mirror.gcr.io/library/node:22-bookworm node:22-bookworm
docker compose up --build --pull never
```

apt のパッケージサーバーに出られない環境では `Dockerfile.source`（strace をソースからビルド）を使います。

```bash
mkdir -p .cache
curl -sSL -o .cache/strace-6.8.tar.xz https://github.com/strace/strace/releases/download/v6.8/strace-6.8.tar.xz
docker build -f Dockerfile.source -t await-strace-lab .
docker run --rm --cap-add SYS_PTRACE --security-opt seccomp=unconfined -v "$PWD/out:/work/out" await-strace-lab
```

### 直接（Linux、strace と Node 22 がある環境）

```bash
cd experiments/nuxt && npm ci && npx nuxt build && cd ../..
bash scripts/run-all.sh          # out/ と out/excerpts/ に出力
```

`scripts/make-excerpts.sh out logs` で、生ログから `logs/` の抜粋だけ作り直すこともできます。

個別に見るときは、

```bash
node experiments/mock.mjs &
strace -f -tt -T -e trace=socket,connect,epoll_pwait,write,read -o out.log node experiments/marks.mjs fetch
grep -nE 'MARK|connect|epoll_pwait' out.log
```

## 読み方のメモ

- `connect(...) = -1 EINPROGRESS` は「接続を OS に預けた」行。ノンブロッキングなので即返る
- `epoll_pwait(15, [...], 1024, 482, NULL, 8) = 1 <0.013712>` が I/O 待ち。Node はこの中で止まっていて CPU を使わない。右端の `<秒>` が待った時間
- Node では、`fetch()` を呼んだだけでは `socket()` すら出ない（Deno は `fetch()` の呼び出し中に `connect()` まで進み、Bun は別スレッドで送受信する。上の Node / Deno / Bun の記事を参照）。JS が手を離して（未解決の Promise を await する、または同期処理が終わる）イベントループに戻ったときに届く
- 直列のログには、1 本目の `epoll_pwait` が終わるまで 2 本目の `connect` が存在しない。この「無い行」が遅さの正体
- `scripts/run-all.sh` の strace は、記録するシステムコールを `socket,connect,epoll_pwait,write,read` の 5 つに絞っている。絞り込みを外すと B だけで 1,700 回ほど出る（`logs/raw/count_B.txt`）
- epoll への登録（`EPOLL_CTL_ADD` / `MOD`）は `epoll_ctl` ではなく `io_uring_enter` で出る。libuv は Linux で epoll の登録を io_uring でまとめて送るため（1.45.0 の ChangeLog「use io_uring to batch epoll_ctl calls」、1.50.0 の ChangeLog「always use io_uring for epoll batching」）（libuv `src/unix/linux.c` の `uv__epoll_ctl_prep` / `uv__epoll_ctl_flush`）。`epoll_ctl` の syscall として出るのは登録の削除（`EPOLL_CTL_DEL`）だけ。`io_uring_enter` の中身（どの操作か）は strace では見えないので、epoll の登録だというのはソースからの判断（`logs/02-epoll-registration-B.txt`）
- io_uring を使うのは epoll の登録だけで、応答を待つのは今も `epoll_pwait`、ソケットの送受信は `write` / `read`。ファイル操作に io_uring（SQPOLL）を使う機能は libuv 1.49.0 から既定で無効で、Node v22.23.3 はそれを有効にしていない（`src/node.cc` の `uv_loop_configure` は `UV_LOOP_BLOCK_SIGNAL` と `UV_METRICS_IDLE_TIME` だけ）
