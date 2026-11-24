# Render a Codex agent definition as TOML, with the body as
# developer_instructions.
#
# Input: agents/<name>.json; the markdown body arrives in $body.
def toml_string: @json;

# Body text is embedded in a TOML multi-line basic string, so backslashes and
# double quotes need escaping. Each replacement doubles or prefixes the matched
# character; jq copies a replacement backslash pair through unchanged.
def instructions:
  $body
  | gsub("\\\\"; "\\\\")
  | gsub("\""; "\\\"")
  | "\"\"\"\n\(.)\n\"\"\"";

[
  "name = \(.name | toml_string)",
  "description = \(.description | toml_string)",
  ((.codex // {}) | to_entries[] | "\(.key) = \(.value | toml_string)"),
  "developer_instructions = \(instructions)"
] | join("\n") + "\n"
