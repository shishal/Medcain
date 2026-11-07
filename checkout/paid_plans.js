// Labels, plus the seed 1-year prices for a fresh database.
// The page shows the rupee amount from paid_plan_catalog (see app.js), not
// from yearAmountPaise here. yearAmountPaise must match paid_plans.ts and
// the y1 seed row. Longer periods are that price times the number of years.
// A live price change is an UPDATE on paid_plan_catalog.
window.BILLING_PERIODS = {
  y1: { months: 12, label: '1 year' },
  y2: { months: 25, label: '2 years + 1 month extra' },
  y3: { months: 38, label: '3 years + 2 months extra' },
  y4: { months: 51, label: '4 years + 3 months extra' },
};

window.PAID_PLANS = {
  pro: {
    yearAmountPaise: 149900,
    currency: 'INR',
    label: 'Pro',
    tagline: 'Full bank, 1 device',
  },
  elite: {
    yearAmountPaise: 299900,
    currency: 'INR',
    label: 'Elite',
    tagline: 'Full bank, 2 devices',
  },
};
