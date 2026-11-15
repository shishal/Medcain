import assert from "node:assert/strict";
import test from "node:test";

import { chooseTarget, isNursingMessage } from "./route.mjs";

test("nursing login and rank stay on nursing", () => {
  assert.equal(isNursingMessage("NURSE login ABCD2345"), true);
  assert.equal(isNursingMessage("nurse rank WEEK1"), true);
  assert.equal(isNursingMessage("MEDCAIN login ABCD2345"), false);
});

test("payloads route by the first matching text", () => {
  const nurse = JSON.stringify({
    entry: [{ changes: [{ value: { messages: [{ type: "text", text: { body: "NURSE RANK WEEK1" } }] } }] }],
  });
  const medico = JSON.stringify({
    entry: [{ changes: [{ value: { messages: [{ type: "text", text: { body: "MEDCAIN login ABCD2345" } }] } }] }],
  });
  assert.equal(chooseTarget(nurse), "nursing");
  assert.equal(chooseTarget(medico), "medico");
  assert.equal(chooseTarget("not json"), "medico");
});
