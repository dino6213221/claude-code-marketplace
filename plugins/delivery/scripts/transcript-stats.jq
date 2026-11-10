# Usage stats of one Claude Code transcript (JSONL read raw: jq -R -s -f transcript-stats.jq <file>).
# Optional window: --argjson from <epoch|null> --argjson to <epoch|null> (only entries inside it count).
# The transcript format is internal to Claude Code — every field access is defensive.
# Output: {start, end, seconds, turns, models, tokens{input,cache_write,cache_read,output}, tools{name:{calls,seconds,result_chars}}, slowest[{tool,label,seconds}]}
# No command text or file content is copied: Bash calls are labeled by program/subcommand only.

def t: if type == "string" and length >= 19
       then (.[0:19] + "Z" | fromdateiso8601) + ((.[20:23] | tonumber? // 0) / 1000)
       else null end;
def inwin: . as $x | ($from == null or ($x != null and $x >= $from)) and ($to == null or ($x != null and $x <= $to));
# Known programs only — anything else (env assignments, paths, arguments) is labeled "bash",
# so no secret, e-mail or customer value can end up in the statistics.
def known_programs: ["warden","reward","ddev","docker","php","composer","git","gh","curl","mysql","mariadb","n98-magerun2",
  "npx","node","npm","yarn","grep","rg","find","ls","cat","head","tail","wc","sed","awk","jq","diff","sort","bash","sh",
  "make","phpunit","phpcs","phpstan","magento2-detect","sleep","test","echo","printf","mkdir","cp","mv","touch","chmod","stat","du"];
def call_label:
  if .name == "Bash" then
    (.input.command // "" | tostring
     | sub("^\\s*(cd [^&;|]+(&&|;)\\s*)+"; "")
     | sub("^\\s*([A-Za-z_][A-Za-z0-9_]*=[^ ]*\\s+)+"; "")) as $c
    | if ($c | test("bin/magento [a-z]+:[a-z:-]+")) then ($c | capture("(?<m>bin/magento [a-z]+:[a-z:-]+)").m)
      elif ($c | test("(^|[ /])(phpunit|phpcs|phpstan)( |$)")) then ($c | capture("(?<m>phpunit|phpcs|phpstan)").m)
      elif ($c | test("^git [a-z-]+")) then ($c | capture("^(?<m>git [a-z-]+)").m)
      else ($c | split(" ") | map(select(length > 0)) | .[0] // "" | split("/") | last) as $p
           | if (known_programs | index([$p])) then $p else "bash" end end
  elif (.name // "" | startswith("mcp__")) then (.name | split("__") | last | gsub("[^A-Za-z0-9_]"; ""))
  else (.name // "tool" | gsub("[^A-Za-z0-9_]"; "")) end;

[split("\n")[] | fromjson? | select(type == "object")]
| map(. + {_t: (.timestamp | t)})
| map(select(._t == null or (._t | inwin)))
| . as $all
| ([$all[] | select(.type == "assistant" and (.message.id // null) != null)]
   | group_by(.message.id) | map(last)) as $msgs
| ([$all[] | select(.type == "assistant") | ._t as $t | (.message.content // [])[]?
   | select(type == "object" and .type == "tool_use")
   | {id, name, label: call_label, t: $t}]) as $uses
| ([$all[] | select(.type == "user") | ._t as $t | (.message.content // [])[]?
   | select(type == "object" and .type == "tool_result")
   | {id: .tool_use_id, t: $t, chars: (.content | tostring | length)}]
   | map({key: .id, value: .}) | from_entries) as $res
| ([$uses[] | . as $u | $res[$u.id] as $r | select($r != null)
   | {tool: $u.name, label: $u.label,
      seconds: (if $u.t != null and $r.t != null then ($r.t - $u.t) else 0 end),
      chars: $r.chars}]) as $calls
| ([$all[] | ._t | select(. != null)]) as $ts
| {
    start: ($ts | min),
    end: ($ts | max),
    seconds: (if ($ts | length) > 0 then (($ts | max) - ($ts | min)) * 10 | round / 10 else 0 end),
    turns: ($msgs | length),
    models: ($msgs | map(.message.model // empty) | unique),
    tokens: {
      input:       ($msgs | map(.message.usage.input_tokens // 0) | add // 0),
      cache_write: ($msgs | map(.message.usage.cache_creation_input_tokens // 0) | add // 0),
      cache_read:  ($msgs | map(.message.usage.cache_read_input_tokens // 0) | add // 0),
      output:      ($msgs | map(.message.usage.output_tokens // 0) | add // 0)
    },
    tools: ($calls | group_by(.tool) | map({key: .[0].tool, value: {
      calls: length, seconds: (map(.seconds) | add | . * 10 | round / 10), result_chars: (map(.chars) | add)}}) | from_entries),
    slowest: ($calls | sort_by(-.seconds) | .[0:5] | map({tool, label, seconds: (.seconds * 10 | round / 10)}))
  }
