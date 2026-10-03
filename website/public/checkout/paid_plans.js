// Labels, plus the seed prices for a fresh database.
// The page shows the rupee amount from paid_plan_catalog (see app.js), not
// from amountPaise here. amountPaise must match paid_plans.ts and the seed
// INSERT so a new database starts at these prices. A live price change is
// an UPDATE on paid_plan_catalog.
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
