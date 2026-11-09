# Invoked as `sh /usr/local/bin/medico-entrypoint.sh` so a shebang is not
# required. nginx's own entrypoint execs /docker-entrypoint.d/*.sh directly,
# and a script it cannot exec shows up as "not found".
set -eu

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

write_public_config() {
  dest=$1
  var_name=$2
  mkdir -p "$(dirname "$dest")"
  if [ -z "$url" ] || [ -z "$key" ]; then
    printf 'window.%s = {"supabaseUrl":"https://YOUR_PROJECT_REF.supabase.co","supabaseAnonKey":""};\n' "$var_name" >"$dest"
  else
    printf 'window.%s = {"supabaseUrl":"%s","supabaseAnonKey":"%s"};\n' "$var_name" "$url" "$key" >"$dest"
  fi
}

write_public_config /usr/share/nginx/html/checkout/config.js CHECKOUT_CONFIG
write_public_config /usr/share/nginx/html/admin/config.js ADMIN_CONFIG

if [ -z "$url" ] || [ -z "$key" ]; then
  echo "site config: SUPABASE_URL / SUPABASE_ANON_KEY missing (url_len=${#url} key_len=${#key}); checkout and admin will show unavailable" >&2
else
  echo "site config: wrote public Supabase settings for checkout and admin" >&2
fi

exec /docker-entrypoint.sh "$@"
