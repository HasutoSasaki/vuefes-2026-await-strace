const base = 'http://127.0.0.1:3000';
const t0 = performance.now();
const ms = () => `${Math.round(performance.now() - t0)}ms`;
const mode = process.argv[2];

if (mode === 'E') {
  // pb は await しない。.then で解決時刻だけ記録する
  const pa = fetch(`${base}/a`);
  const pb = fetch(`${base}/b`);
  pb.then(() => console.log(`pb resolved  ${ms()}  (await していない)`));
  await pa;
  console.log(`pa resolved  ${ms()}`);
  await new Promise(r => setTimeout(r, 200)); // pb の then が出るのを待つだけ
}

if (mode === 'F') {
  // fetch を呼んだ直後に JS が 1 秒間手を離さない（同期ビジーループ）
  const pa = fetch(`${base}/a`);
  process.stdout.write(`MARK fetch called ${ms()}\n`);
  const end = performance.now() + 1000;
  while (performance.now() < end) {}
  process.stdout.write(`MARK busy done   ${ms()}\n`);
  await pa;
  console.log(`pa resolved  ${ms()}`);
}
