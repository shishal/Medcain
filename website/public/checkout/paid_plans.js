// Display-only copy of supabase/functions/_shared/paid_plans.ts.
// The Pay button does not send these amounts — Razorpay charges whatever
// the Edge Function put on the Order.
window.PAID_PLANS = {
  pro: {
    amountPaise: 149900,
    currency: 'INR',
    durationDays: 180,
    periodLabel: '6 months',
    label: 'Pro',
    description: '6 months of Pro',
    tagline: 'Serious daily practice',
  },
  elite: {
    amountPaise: 299900,
    currency: 'INR',
    durationDays: 365,
    periodLabel: '12 months',
    label: 'Elite',
    description: '12 months of Elite',
    tagline: 'Everything unlocked',
  },
};
