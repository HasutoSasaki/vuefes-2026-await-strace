<script setup lang="ts">
// 束ね: 2本届けてから I/O 待ち
if (import.meta.server) process.stdout.write('MARK parallel start\n')
const [{ data: a }, { data: b }] = await Promise.all([
  useFetch('http://127.0.0.1:3000/a'),
  useFetch('http://127.0.0.1:3000/b'),
])
if (import.meta.server) process.stdout.write('MARK parallel end\n')
</script>
<template>
  <div>parallel: {{ a }} / {{ b }}</div>
</template>
