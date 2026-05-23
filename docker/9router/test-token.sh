API_KEY="${1}"

if [ -z "${API_KEY}" ]; then
  echo "API_KEY NOT INPUT"
  exit 1
fi

CDN="$(grep "CDN" .env | awk -F'=' '{print $2}')"
URL="${CDN}/v1/chat/completions"

curl ${URL} \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-3.5-flash",
    "messages": [{"role": "user", "content": "Halo, ini adalah tes pertama untuk fitur monitoring token."}]
  }'
