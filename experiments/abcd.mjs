const base = 'http://127.0.0.1:3000';
const mode = process.argv[2];

const t0 = performance.now();
let a, b;

if (mode === 'A') {
  // 直列
  a = await fetch(`${base}/a`);
  b = await fetch(`${base}/b`);
} else if (mode === 'B') {
  // Promise.all で束ね
  [a, b] = await Promise.all([fetch(`${base}/a`), fetch(`${base}/b`)]);
} else if (mode === 'C') {
  // 先に両方呼んでから個別に await
  const pa = fetch(`${base}/a`);
  const pb = fetch(`${base}/b`);
  a = await pa;
  b = await pb;
} else if (mode === 'D') {
  // Promise.all を使っても直列
  a = await fetch(`${base}/a`);
  [b] = await Promise.all([fetch(`${base}/b`)]);
}

await a.text(); await b.text();
console.log(`${mode}: ${Math.round(performance.now() - t0)} ms`);
