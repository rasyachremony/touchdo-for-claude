#!/bin/bash
# Optional, needs jq: paste into your Claude Code status line script, right after it has read stdin into $input
# (input=$(cat)). TouchDo's bars then follow every reply instead of waiting for the 1-minute refresh.
usage_dir="$HOME/Library/Application Support/io.github.rasyachremony.TouchDo"
if [ -d "$usage_dir" ] && jq -e '.rate_limits.five_hour or .rate_limits.seven_day' >/dev/null 2>&1 <<<"$input"; then
  # Several sessions may run at once: per window keep the newest reading (later reset, then higher use).
  usage=$(jq -c --arg old "$(cat "$usage_dir/usage.json" 2>/dev/null)" '
    def pick($a; $b): if $b == null then $a elif $a == null then $b
      elif [$a.resets_at // 0, $a.used_percentage // 0] >= [$b.resets_at // 0, $b.used_percentage // 0] then $a else $b end;
    (((try ($old | fromjson) catch null) | objects) // {}) as $o
    | $o + {five_hour: pick(.rate_limits.five_hour; $o.five_hour), seven_day: pick(.rate_limits.seven_day; $o.seven_day)}
  ' <<<"$input") && printf '%s\n' "$usage" >"$usage_dir/usage.json.$$" && mv "$usage_dir/usage.json.$$" "$usage_dir/usage.json"
fi
