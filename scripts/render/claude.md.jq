# Render a Claude Code agent definition: YAML frontmatter over the system prompt.
#
# Input: agents/<name>.json; the markdown body arrives in $body.
def yaml:
  if type == "string" then @json else tostring end;

def front_matter:
  [
    "---",
    "name: \(.name)",
    "description: \(.description | yaml)",
    ((.claude // {}).tools | select(. != null) | "tools: \(join(", "))"),
    ((.claude // {})
      | to_entries[]
      | select(.key != "tools")
      | if (.value | type) == "array" then
          "\(.key): [\([.value[] | yaml] | join(", "))]"
        else
          "\(.key): \(.value | yaml)"
        end)
  ];

[ (front_matter[]), "---", "", $body ] | join("\n") + "\n"
