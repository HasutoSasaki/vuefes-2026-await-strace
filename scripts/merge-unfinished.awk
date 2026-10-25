# strace -f の "<unfinished ...>" 行と、同じ pid の "<... xxx resumed>" 行を 1 行につなげる
{
  pid = $1
  if ($0 ~ /<unfinished \.\.\.>$/) { sub(/ <unfinished \.\.\.>$/, "", $0); pend[pid] = $0; next }
  if ($0 ~ /<\.\.\. [a-z_0-9]+ resumed>/ && (pid in pend)) {
    rest = $0; sub(/^.*<\.\.\. [a-z_0-9]+ resumed>/, "", rest)
    print pend[pid] rest; delete pend[pid]; next
  }
  print
}
