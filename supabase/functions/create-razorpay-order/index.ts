// Creates a Razorpay Order for the signed-in user.
// Amount comes from paid_plans.ts — never from the request body.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { getPaidPlan } from '../_shared/paid_plans.ts';

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

  if (userError || user == null || user.email == null) {
    return jsonResponse({ error: 'Sign in to continue.' }, 401);
  }

  let planName = '';
  let requestedCode: string | null = null;
  try {
    const body = await req.json();
    planName = typeof body?.plan === 'string' ? body.plan.trim().toLowerCase() : '';
    if (typeof body?.code === 'string' && body.code.trim().length > 0) {
      requestedCode = body.code.trim();
    }
  } catch {
    return jsonResponse({ error: 'Send JSON with a plan field.' }, 400);
  }

  const plan = getPaidPlan(planName);
  if (plan == null) {
    return jsonResponse({ error: 'Choose Pro or Elite.' }, 400);
  }

  // Amount comes from checkout_quote(), never from this request.
  const { data: quote, error: quoteError } = await supabase.rpc(
    'checkout_quote',
    { p_plan: planName, p_code: requestedCode },
  );

  if (quoteError) {
    const known = [
      'That code is not valid.',
      'That code has expired.',
      'That code has been used up.',
      'Referral codes cannot be used on your own payment.',
      'You already used this code.',
      'That discount is too large for this plan.',
      'Choose Pro or Elite.',
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

  const discountCode = typeof quote.code === 'string' ? quote.code : null;
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
  const receipt = `m_${planName}_${Date.now().toString(36)}`;

  const notes: Record<string, string> = {
    user_id: user.id,
    plan: planName,
    email: user.email,
  };
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

  return jsonResponse({
    keyId,
    orderId: razorpayBody.id,
    amount: amountPaise,
    listAmount: listAmountPaise,
    percentOff,
    code: discountCode,
    currency: 'INR',
    plan: planName,
    label: plan.label,
    description: percentOff
      ? `${plan.description} · ${percentOff}% off`
      : plan.description,
    name: 'Medico',
    prefillEmail: user.email,
  });
});
