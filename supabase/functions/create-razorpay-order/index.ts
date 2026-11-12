// Creates a Razorpay Order for the signed-in user.
// Amount comes from checkout_quote() → plans.amount_paise, never from the body.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import { isSyntheticEmail } from '../_shared/whatsapp_auth.ts';
import { corsHeaders, jsonResponse } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'Sign in to continue.' }, 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: 'Server is missing Supabase config.' }, 500);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || user == null) {
    return jsonResponse({ error: 'Sign in to continue.' }, 401);
  }

  const phone = typeof user.phone === 'string' && user.phone.length > 0
    ? user.phone
    : null;
  const email = typeof user.email === 'string' &&
      user.email.length > 0 &&
      !isSyntheticEmail(user.email)
    ? user.email
    : null;
  if (phone == null && email == null) {
    return jsonResponse({ error: 'Sign in to continue.' }, 401);
  }

  const planIdPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  let planId = '';
  let requestedCode: string | null = null;
  try {
    const body = await req.json();
    planId = typeof body?.plan_id === 'string' ? body.plan_id.trim() : '';
    if (typeof body?.code === 'string' && body.code.trim().length > 0) {
      requestedCode = body.code.trim();
    }
  } catch {
    return jsonResponse({ error: 'Send JSON with a plan_id field.' }, 400);
  }

  if (!planIdPattern.test(planId)) {
    return jsonResponse({ error: 'Choose a plan.' }, 400);
  }

  // Amount comes from checkout_quote(), never from this request.
  const { data: quote, error: quoteError } = await supabase.rpc(
    'checkout_quote',
    { p_plan_id: planId, p_code: requestedCode },
  );

  if (quoteError) {
    const known = [
      'That code is not valid.',
      'That code has expired.',
      'That code has been used up.',
      'Referral codes cannot be used on your own payment.',
      'You already used this code.',
      'That discount is too large for this plan.',
      'Choose a plan.',
      'Sign in to continue.',
    ];
    const message = known.find((item) => quoteError.message.includes(item));
    return jsonResponse(
      { error: message ?? 'Could not start checkout. Please try again.' },
      message ? 400 : 500,
    );
  }

  const amountPaise = quote?.amount_paise;
  const listAmountPaise = quote?.list_amount_paise;
  if (
    typeof amountPaise !== 'number' ||
    typeof listAmountPaise !== 'number' ||
    quote?.currency !== 'INR'
  ) {
    return jsonResponse(
      { error: 'Could not start checkout. Please try again.' },
      500,
    );
  }

  const discountCode = typeof quote.discount_code === 'string'
    ? quote.discount_code
    : null;
  const percentOff = typeof quote.percent_off === 'number'
    ? quote.percent_off
    : null;

  const keyId = Deno.env.get('RAZORPAY_KEY_ID');
  const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET');
  if (!keyId || !keySecret) {
    return jsonResponse(
      { error: 'Checkout is not configured yet. Try again later.' },
      500,
    );
  }

  // receipt max 40 chars. Date.now() in base36 stays well under that.
  const receipt = `m_${planId.slice(0, 8)}_${Date.now().toString(36)}`;

  const notes: Record<string, string> = {
    user_id: user.id,
    plan_id: planId,
  };
  if (email) notes.email = email;
  if (phone) notes.phone = phone;
  if (discountCode) notes.discount_code = discountCode;

  const razorpayResponse = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount: amountPaise,
      currency: 'INR',
      receipt,
      notes,
    }),
  });

  const razorpayBody = await razorpayResponse.json();
  if (!razorpayResponse.ok) {
    console.error('Razorpay Orders API error', razorpayBody);
    return jsonResponse(
      { error: 'Could not start checkout. Please try again.' },
      502,
    );
  }

  const planName = typeof quote.name === 'string' ? quote.name : 'Plan';
  const durationLabel = typeof quote.duration_label === 'string' &&
      quote.duration_label.length > 0
    ? quote.duration_label
    : typeof quote.duration_months === 'number'
    ? `${quote.duration_months} months`
    : '';
  const description = [planName, durationLabel, percentOff ? `${percentOff}% off` : '']
    .filter((part) => part.length > 0)
    .join(' · ');

  return jsonResponse({
    keyId,
    orderId: razorpayBody.id,
    amount: amountPaise,
    listAmount: listAmountPaise,
    percentOff,
    code: discountCode,
    currency: 'INR',
    plan_id: planId,
    label: planName,
    description,
    name: 'Medico',
    prefillEmail: email,
    prefillPhone: phone,
  });
});
