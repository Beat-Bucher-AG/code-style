#!/usr/bin/env bash
set -euo pipefail

T="$RUNNER_TEMP/code-style/templates"
V="$RUNNER_TEMP/code-style/versions"
LINK="https://github.com/Beat-Bucher-AG/code-style/tree/main/templates"
errors=0

fail() { echo "::error::$1"; errors=$((errors + 1)); }
same() { diff -q "$1" "$T/$2/$1" > /dev/null 2>&1 || fail "$1 fehlt oder weicht ab. Vorlage: $LINK/$2"; }
allowed() { grep -qxF "$1" "$2"; }
list() { grep -v '^[[:space:]]*$' "$1" | paste -sd ' ' -; }
latest() { grep -v '^[[:space:]]*$' "$1" | tail -n 1; }

same .editorconfig shared
same .gitattributes shared
same lefthook.yml shared

if [ -n "$(git ls-files '*.csproj')" ]; then
  same Directory.Build.targets dotnet
  CSHARPIER_VERSION=$(jq -r '.tools.csharpier.version // "fehlt"' .config/dotnet-tools.json 2>/dev/null || echo fehlt)
  allowed "$CSHARPIER_VERSION" "$V/csharpier" \
    || fail "CSharpier muss mit einer erlaubten Version in .config/dotnet-tools.json stehen (gefunden: $CSHARPIER_VERSION, erlaubt: $(list "$V/csharpier")). Fix: dotnet tool update csharpier --version $(latest "$V/csharpier")"
fi

if [ -f package.json ]; then
  same .prettierrc node
  actual=$(jq -r '.devDependencies.prettier // "fehlt"' package.json)
  allowed "$actual" "$V/prettier" \
    || fail "prettier muss exakt eine erlaubte Version sein (gefunden: $actual, erlaubt: $(list "$V/prettier")). Fix: npm install --save-dev --save-exact prettier@$(latest "$V/prettier")"
  for plugin in $(jq -r '.plugins[]?' "$T/node/.prettierrc"); do
    jq -e --arg p "$plugin" '.devDependencies[$p]' package.json > /dev/null \
      || fail "$plugin fehlt. Fix: npm install --save-dev --save-exact $plugin"
  done
  jq -e '.devDependencies.lefthook' package.json > /dev/null \
    || fail "lefthook fehlt. Fix: npm install --save-dev lefthook"
fi

[ "$errors" -eq 0 ] || exit 1

if [ -n "$(git ls-files '*.csproj')" ]; then
  dotnet tool install csharpier --version "$CSHARPIER_VERSION" --tool-path "$RUNNER_TEMP/tools"
  "$RUNNER_TEMP/tools/csharpier" check .
fi

if [ -f package.json ]; then
  npm ci --ignore-scripts
  npx prettier --check .
fi
