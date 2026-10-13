const base = 'http://127.0.0.1:3000';
const t0 = performance.now();
const ms = () => `${Math.round(performance.now() - t0)}ms`;
const mark = (s) => process.stdout.write(`MARK ${s} ${ms()}\n`);
const busy = (n) => { const end = performance.now() + n; while (performance.now() < end) {} };
const mode = process.argv[2];

const pa = fetch(`${base}/a`);
mark('fetch called');

if (mode === 'G') {
  // マイクロタスクだけの await（イベントループには戻らない）
  await Promise.resolve();
  mark('after await Promise.resolve');
} else if (mode === 'H') {
  // タイマーの await（イベントループまで戻る）
  await new Promise(r => setTimeout(r, 0));
  mark('after await setTimeout0');
}

busy(500);
mark('busy done');
await pa;
mark('pa resolved');
