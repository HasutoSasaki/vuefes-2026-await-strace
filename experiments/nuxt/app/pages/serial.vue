<script setup lang="ts">
// 直列: 1本届けて I/O 待ち、戻ってから次
if (import.meta.server) process.stdout.write('MARK serial start\n')
const { data: a } = await useFetch('http://127.0.0.1:3000/a')
const { data: b } = await useFetch('http://127.0.0.1:3000/b')
if (import.meta.server) process.stdout.write('MARK serial end\n')
</script>
<template>
  <div>serial: {{ a }} / {{ b }}</div>
</template>
