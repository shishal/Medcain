# Invoked as `sh /usr/local/bin/medico-entrypoint.sh` so a shebang is not
# required. nginx's own entrypoint execs /docker-entrypoint.d/*.sh directly,
# and a script it cannot exec shows up as "not found".
set -eu

out=/usr/share/nginx/html/checkout/config.js
url=${SUPABASE_URL:-}
key=${SUPABASE_ANON_KEY:-}

# .env values sometimes arrive with a Windows CR or wrapping quotes.
url=$(printf '%s' "$url" | tr -d '\r')
key=$(printf '%s' "$key" | tr -d '\r')
case $url in
  \"*\") url=${url#\"}; url=${url%\"} ;;
  \'*\') url=${url#\'}; url=${url%\'} ;;
esac
case $key in
  \"*\") key=${key#\"}; key=${key%\"} ;;
  \'*\') key=${key#\'}; key=${key%\'} ;;
esac

case "$url$key" in
  *\"*|*\\*)
    echo "checkout config: refusing quotes or backslashes in SUPABASE_URL or SUPABASE_ANON_KEY" >&2
    url=""
    key=""
    ;;
esac

case "$url" in
  *YOUR_PROJECT*) url="" ;;
esac

if [ -z "$url" ] || [ -z "$key" ]; then
  printf '%s\n' 'window.CHECKOUT_CONFIG = {"supabaseUrl":"https://YOUR_PROJECT_REF.supabase.co","supabaseAnonKey":""};' >"$out"
  echo "checkout config: SUPABASE_URL / SUPABASE_ANON_KEY missing (url_len=${#url} key_len=${#key}); checkout will show unavailable" >&2
else
  printf 'window.CHECKOUT_CONFIG = {"supabaseUrl":"%s","supabaseAnonKey":"%s"};\n' "$url" "$key" >"$out"
  echo "checkout config: wrote public Supabase settings" >&2
fi

exec /docker-entrypoint.sh "$@"
