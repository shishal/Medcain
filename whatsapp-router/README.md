# Shared WhatsApp router

Meta allows one webhook URL per WhatsApp number. This process is that URL.
It forwards the raw body and `X-Hub-Signature-256` unchanged.

- `NURSE LOGIN …` and `NURSE RANK …` go to the nursing app.
- Every other message, including `MEDCAIN login …`, goes to MEDCAIN.
- A payload that mixes both is forwarded to both apps. Each app ignores what it does not understand.

This folder stays outside the nursing repo. The live callback does not need this process: Meta already points at MEDCAIN's `whatsapp-webhook`, and that function forwards `NURSE LOGIN` and `NURSE RANK` to `NURSING_WEBHOOK_URL`. Use this Node server only if you later want the callback hosted somewhere else. Both apps must use the same Meta app secret, because both still check the signature.

```bash
export WHATSAPP_VERIFY_TOKEN=...
export MEDICO_WEBHOOK_URL='https://<medico>.supabase.co/functions/v1/whatsapp-webhook?apikey=<anon>'
export NURSING_WEBHOOK_URL='https://<nursing>.supabase.co/functions/v1/whatsapp-webhook?apikey=<anon>'
node server.mjs
```

`node --test route.test.mjs` checks the routing rules.
