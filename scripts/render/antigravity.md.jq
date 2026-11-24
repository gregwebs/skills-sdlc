# Render an Antigravity agent definition: YAML frontmatter over the system
# prompt.
#
# Input: agents/<name>.json; the markdown body arrives in $body. Antigravity
# defaults mainAgent to true, so every installed agent is pinned as a subagent.
def yaml:
  if type == "string" then @json else tostring end;

def field($key; $value):
  if ($value | type) == "array" then
    "\($key):\n\([$value[] | "  - \(yaml)"] | join("\n"))"
  else
    "\($key): \($value | yaml)"
  end;

[
  "---",
  "name: \(.name)",
  "description: \(.description | yaml)",
  "subagent: \(.antigravity.subagent // true)",
  "mainAgent: \(.antigravity.mainAgent // false)",
  ((.antigravity // {})
    | to_entries[]
    | select(.key != "subagent" and .key != "mainAgent")
    | field(.key; .value)),
  "---",
  "",
  $body
] | join("\n") + "\n"
