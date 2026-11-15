// One WhatsApp number can have one webhook. This picks which app receives it.
// NURSE LOGIN and NURSE RANK go to the nursing app. Everything else stays on MEDCAIN.

export function textBodies(payload) {
  const bodies = [];
  const entries = Array.isArray(payload?.entry) ? payload.entry : [];
  for (const entry of entries) {
    const changes = Array.isArray(entry?.changes) ? entry.changes : [];
    for (const change of changes) {
      const messages = change?.value?.messages;
      if (!Array.isArray(messages)) continue;
      for (const message of messages) {
        if (message?.type === "text" && typeof message.text?.body === "string") {
          bodies.push(message.text.body);
        }
      }
    }
  }
  return bodies;
}

export function isNursingMessage(body) {
  return /^NURSE\s+(LOGIN|RANK)\b/i.test(body.trim());
}

/** @returns {'nursing' | 'medico' | 'both'} */
export function chooseTarget(rawBody) {
  let payload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return "medico";
  }
  const bodies = textBodies(payload);
  if (bodies.length === 0) return "medico";
  const nursing = bodies.some(isNursingMessage);
  const other = bodies.some((body) => !isNursingMessage(body));
  if (nursing && other) return "both";
  return nursing ? "nursing" : "medico";
}
