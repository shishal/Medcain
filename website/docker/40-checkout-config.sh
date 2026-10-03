#!/bin/sh
# Writes the public Supabase settings the checkout page needs.
# Razorpay secrets must never be passed into this container.
set -eu

out=/usr/share/nginx/html/checkout/config.js
url=${SUPABASE_URL:-}
key=${SUPABASE_ANON_KEY:-}

case "$url$key" in
  *\"*|*\\*)
    echo "checkout config: refusing quotes or backslashes in SUPABASE_URL or SUPABASE_ANON_KEY" >&2
    url=""
    key=""
    ;;
esac

if [ -z "$url" ] || [ -z "$key" ] || echo "$url" | grep -q 'YOUR_PROJECT'; then
  printf '%s\n' 'window.CHECKOUT_CONFIG = {"supabaseUrl":"https://YOUR_PROJECT_REF.supabase.co","supabaseAnonKey":""};' >"$out"
  echo "checkout config: SUPABASE_URL / SUPABASE_ANON_KEY missing; checkout will show unavailable" >&2
else
  printf 'window.CHECKOUT_CONFIG = {"supabaseUrl":"%s","supabaseAnonKey":"%s"};\n' "$url" "$key" >"$out"
  echo "checkout config: wrote public Supabase settings" >&2
fi
