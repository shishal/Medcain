// Razorpay → profiles.plan. Signature is the only auth (verify_jwt = false).
// An unsigned body must never grant a plan.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  isValidRazorpaySignature,
  parseWebhookEvent,
} from '../_shared/razorpay_webhook.ts';

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const secret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET');
  if (secret == null || secret.length === 0) {
    console.error('RAZORPAY_WEBHOOK_SECRET is not set');
    return json({ error: 'Webhook is not configured' }, 500);
  }

  const rawBody = await req.text();
  const signature = req.headers.get('X-Razorpay-Signature');
  const ok = await isValidRazorpaySignature(rawBody, signature, secret);
  if (!ok) {
    return json({ error: 'Invalid signature' }, 400);
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(rawBody);
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = parseWebhookEvent(parsedJson);
  if (parsed.kind === 'ignored') {
    return json({ received: true, ignored: parsed.event }, 200);
  }
  if (parsed.kind === 'invalid') {
    console.error(`razorpay-webhook rejected: ${parsed.reason}`);
    return json({ error: parsed.reason }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (supabaseUrl == null || serviceRoleKey == null) {
    console.error('Supabase service role env is missing');
    return json({ error: 'Server is missing Supabase config' }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const pay = parsed.payment;
  const { data, error } = await admin.rpc('apply_razorpay_payment', {
    p_payment_id: pay.paymentId,
    p_order_id: pay.orderId,
    p_user_id: pay.userId,
    p_plan: pay.plan,
    p_amount_paise: pay.amountPaise,
    p_currency: pay.currency,
    p_discount_code: pay.discountCode,
  });

  if (error) {
    console.error('apply_razorpay_payment failed', error.message);
    return json({ error: 'Could not apply payment' }, 500);
  }

  console.log(
    `razorpay-webhook payment=${pay.paymentId} user=${pay.userId} plan=${pay.plan} duplicate=${data?.duplicate === true}`,
  );

  return json({ received: true, ...data }, 200);
});
