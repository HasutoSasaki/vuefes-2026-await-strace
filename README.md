# あなたの await、OS まで届いてる？ — strace で覗く JavaScript の非同期

Vue Fes Japan 2026（2026-10-24）LT の検証一式です。Node.js の `await` が OS にどう届いているかを `strace` で観察します。

- スライド: （公開後に追記）
- 関連記事（DevelopersIO）
  - [Node.js の非同期処理をシステムコールから覗く](https://dev.classmethod.jp/articles/nodejs-async-deep-dive-with-syscalls/)
  - [Node.js の fetch を strace で追う](https://dev.classmethod.jp/articles/nodejs-fetch-strace/)
  - [複数 fetch の直列 vs Promise.all を strace で比べる](https://dev.classmethod.jp/articles/nodejs-multiple-fetch-strace/)

## 3 つの問い

| # | 問い | 答え | ログ |
|---|---|---|---|
| 1 | あなたの await、OS まで届いてる？ | 届く await と、届かない await がある | [logs/01](logs/01-marks-resolve-vs-fetch.txt) |
| 2 | 直列と Promise.all、OS から見ると何が違う？ | 直列は 1 本届けて I/O 待ち。束ねると全部届けてから I/O 待ち | [logs/02](logs/02-strace-A-vs-C.txt) |
| 3 | なぜ束ねると速いのか？ | I/O 待ちに入る前に全部届けているから。OS は何本でも同時に待てる | [logs/03](logs/03-nuxt-serial-vs-parallel.txt) |

何本届けてから待つかは、手を離す前に何本呼んだかで決まる。

## 実験

モックサーバー（`experiments/mock.mjs`）は `127.0.0.1:3000` で `/a` `/b` に 300ms 固定遅延で応答します。

| ファイル | 内容 |
|---|---|
| `experiments/marks.mjs` | ① `process.stdout.write` の印で挟み、`await Promise.resolve()` と `await fetch()` の間に出るシステムコールを比べる |
| `experiments/abcd.mjs` | ② A 直列 / B `Promise.all` / C 先に 2 本呼んで個別 await / D 1 本 await 後に `Promise.all` の所要時間 |
| `experiments/fire.mjs` | F: `fetch()` 直後に 1 秒ビジーループ。その間 `socket()` が出ないことを見る |
| `experiments/yield.mjs` | G: `await Promise.resolve()` ではイベントループに戻らない / H: `await setTimeout(0)` では戻って `connect` が出る |
| `experiments/nuxt/` | ③ Nuxt 4 SSR で `await useFetch` 直列と `Promise.all` を比べる最小アプリ |

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

strace の抜粋は `logs/*.txt`、生ログは `logs/raw/`、取得環境は `logs/ENV.txt` にあります。

> **`logs/` の出どころ**: 標準の `Dockerfile` でビルドしたコンテナ（node:22-bookworm、strace は apt の 6.1、macOS の Docker Desktop 上の aarch64）で `scripts/run-all.sh` を実行し、`out/excerpts/` をそのままコピーしたものです。手作業の整形はしていません。`docker compose up --build` を実行すると同じ形式で再生成されます。

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
- `epoll_pwait(15, [...], 1024, 491, NULL, 8) = 1 <0.30xxxx>` が I/O 待ち。Node はこの中で止まっていて CPU を使わない。右端の `<秒>` が待った時間
- `fetch()` を呼んだだけでは `socket()` すら出ない。JS が手を離して（未解決の Promise を await する、または同期処理が終わる）イベントループに戻ったときに届く
- 直列のログには、1 本目の `epoll_pwait` が終わるまで 2 本目の `connect` が存在しない。この「無い行」が遅さの正体
