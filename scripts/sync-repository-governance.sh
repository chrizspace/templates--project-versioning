#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${GOVERNANCE_CONFIG:-"$SCRIPT_DIR/../config/repository-governance.json"}"
REPOSITORY="${GH_REPO:-}"

if [[ -z "$REPOSITORY" ]]; then
  REPOSITORY="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi

if [[ -z "$REPOSITORY" ]]; then
  echo "Unable to determine the target repository. Set GH_REPO to OWNER/REPOSITORY." >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Governance configuration not found: $CONFIG_FILE" >&2
  exit 1
fi

jq empty "$CONFIG_FILE"

echo "Synchronizing governance for $REPOSITORY"

default_branch="$(gh api "repos/$REPOSITORY" --jq '.default_branch')"
default_sha="$(gh api "repos/$REPOSITORY/git/ref/heads/$default_branch" --jq '.object.sha')"
branches="$(
  gh api \
    --paginate \
    --slurp \
    "repos/$REPOSITORY/branches?per_page=100" |
    jq 'add // []'
)"

while IFS= read -r branch; do
  if jq -e --arg branch "$branch" 'any(.[]; .name == $branch)' <<< "$branches" >/dev/null; then
    echo "  branch: $branch (exists)"
    continue
  fi

  gh api \
    --method POST \
    -f "ref=refs/heads/$branch" \
    -f "sha=$default_sha" \
    "repos/$REPOSITORY/git/refs" >/dev/null
  echo "  branch: $branch (created from $default_branch)"
done < <(jq -r '.branches[]' "$CONFIG_FILE")

labels="$(
  gh api \
    --paginate \
    --slurp \
    "repos/$REPOSITORY/labels?per_page=100" |
    jq 'add // []'
)"

while IFS= read -r label; do
  name="$(jq -r '.name' <<< "$label")"
  color="$(jq -r '.color' <<< "$label")"
  description="$(jq -r '.description' <<< "$label")"
  existing_name="$(jq -r --arg name "$name" 'first(.[] | select(.name == $name) | .name) // empty' <<< "$labels")"

  if [[ -n "$existing_name" ]]; then
    encoded_name="$(jq -nr --arg value "$existing_name" '$value | @uri')"
    jq -n \
      --arg name "$name" \
      --arg color "$color" \
      --arg description "$description" \
      '{new_name: $name, color: $color, description: $description}' |
      gh api \
        --method PUT \
        --input - \
        "repos/$REPOSITORY/labels/$encoded_name" >/dev/null

    echo "  label: $name (PUT)"
  else
    jq -n \
      --arg name "$name" \
      --arg color "$color" \
      --arg description "$description" \
      '{name: $name, color: $color, description: $description}' |
      gh api \
        --method POST \
        --input - \
        "repos/$REPOSITORY/labels" >/dev/null

    echo "  label: $name (POST)"
  fi
done < <(jq -c '.labels[]' "$CONFIG_FILE")

labels="$(
  gh api \
    --paginate \
    --slurp \
    "repos/$REPOSITORY/labels?per_page=100" |
    jq 'add // []'
)"

while IFS= read -r label; do
  name="$(jq -r '.name' <<< "$label")"
  if jq -e --arg name "$name" 'any(.labels[]; .name == $name)' "$CONFIG_FILE" >/dev/null; then
    continue
  fi

  encoded_name="$(jq -nr --arg value "$name" '$value | @uri')"
  gh api \
    --method DELETE \
    "repos/$REPOSITORY/labels/$encoded_name" >/dev/null
  echo "  label: $name (DELETE)"
done < <(jq -c '.[]' <<< "$labels")

rulesets="$(
  gh api \
    --paginate \
    --slurp \
    "repos/$REPOSITORY/rulesets?includes_parents=false&per_page=100" |
    jq 'add // []'
)"

while IFS= read -r ruleset; do
  name="$(jq -r '.name' <<< "$ruleset")"
  id="$(jq -r --arg name "$name" 'first(.[] | select(.name == $name) | .id) // empty' <<< "$rulesets")"
  endpoint="repos/$REPOSITORY/rulesets"
  method="POST"

  if [[ -n "$id" ]]; then
    endpoint="$endpoint/$id"
    method="PUT"
  fi

  jq '{name, target, enforcement, conditions, rules, bypass_actors}' <<< "$ruleset" |
    gh api \
      --method "$method" \
      --input - \
      "$endpoint" >/dev/null

  echo "  ruleset: $name ($method)"
done < <(jq -c '.rulesets[]' "$CONFIG_FILE")

rulesets="$(
  gh api \
    --paginate \
    --slurp \
    "repos/$REPOSITORY/rulesets?includes_parents=false&per_page=100" |
    jq 'add // []'
)"

while IFS= read -r ruleset; do
  id="$(jq -r '.id' <<< "$ruleset")"
  name="$(jq -r '.name' <<< "$ruleset")"
  configured_name="$(
    jq -r --arg name "$name" \
      'first(.rulesets[] | select(.name == $name) | .name) // empty' \
      "$CONFIG_FILE"
  )"

  if [[ "$name" == "$configured_name" ]]; then
    continue
  fi

  gh api \
    --method DELETE \
    "repos/$REPOSITORY/rulesets/$id" >/dev/null
  echo "  ruleset: $name (DELETE)"
done < <(jq -c '.[]' <<< "$rulesets")

echo "Governance synchronization complete."
