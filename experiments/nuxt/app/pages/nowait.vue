<script setup lang="ts">
// await を付けない: 2 本とも呼んでから setup を抜ける
if (import.meta.server) process.stdout.write('MARK nowait start\n')
const { data: a } = useFetch('http://127.0.0.1:3000/a')
const { data: b } = useFetch('http://127.0.0.1:3000/b')
if (import.meta.server) process.stdout.write('MARK nowait end\n')
</script>
<template>
  <div>nowait: {{ a }} / {{ b }}</div>
</template>
