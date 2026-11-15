import http from "node:http";

import { chooseTarget } from "./route.mjs";

const port = Number(process.env.PORT || 8787);
const medicoUrl = process.env.MEDICO_WEBHOOK_URL || "";
const nursingUrl = process.env.NURSING_WEBHOOK_URL || "";
const verifyToken = process.env.WHATSAPP_VERIFY_TOKEN || "";

function sha256Hex(value) {
  return import("node:crypto").then((crypto) =>
    crypto.createHash("sha256").update(value).digest("hex")
  );
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET") {
    const url = new URL(req.url, "http://router.local");
    const mode = url.searchParams.get("hub.mode");
    const provided = url.searchParams.get("hub.verify_token") ?? "";
    const challenge = url.searchParams.get("hub.challenge") ?? "";
    const [got, expected] = await Promise.all([
      sha256Hex(provided),
      sha256Hex(verifyToken),
    ]);
    if (mode !== "subscribe" || got !== expected || challenge.length === 0) {
      res.writeHead(403);
      res.end("Forbidden");
      return;
    }
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(challenge);
    return;
  }

  if (req.method !== "POST") {
    res.writeHead(405);
    res.end("Method not allowed");
    return;
  }

  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks);
  const target = chooseTarget(raw.toString("utf8"));
  const urls = target === "both"
    ? [nursingUrl, medicoUrl]
    : [target === "nursing" ? nursingUrl : medicoUrl];

  let status = 200;
  let body = '{"ok":true}';
  for (const url of urls) {
    if (!url) {
      status = 500;
      body = '{"error":"Webhook URL is not set"}';
      continue;
    }
    const upstream = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": req.headers["content-type"] || "application/json",
        "x-hub-signature-256": req.headers["x-hub-signature-256"] || "",
      },
      body: raw,
    });
    status = upstream.status;
    body = await upstream.text();
  }
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(body);
});

server.listen(port, () => {
  console.log(`WhatsApp router listening on ${port}`);
});
