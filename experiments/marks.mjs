// ① 印と印の間に何が出るか: await Promise.resolve() vs await fetch()
const base = 'http://127.0.0.1:3000';
const mode = process.argv[2];

process.stdout.write('MARK A\n');
if (mode === 'resolve') {
  await Promise.resolve();
} else if (mode === 'fetch') {
  const res = await fetch(`${base}/a`);
  await res.text();
}
process.stdout.write('MARK B\n');
