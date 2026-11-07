/// Labels, and the seed 1-year prices for a fresh database.
///
/// The live rupee amount is `paid_plan_catalog.amount_paise` for a plan and
/// a period (`y1`…`y4`). Orders and the webhook do not charge from
/// `yearAmountPaise` here. Change a live price with UPDATE on that table
/// (see docs/06_PAYMENTS_PRODUCTION.md).
///
/// `yearAmountPaise` must match the `y1` seed row. Longer periods are that
/// price times the number of years. The extra months are free time, not an
/// extra charge.

export type PaidPlanId = 'pro' | 'elite';
export type BillingPeriodId = 'y1' | 'y2' | 'y3' | 'y4';

export interface PaidPlan {
  yearAmountPaise: number;
  currency: 'INR';
  label: string;
  tagline: string;
}

export interface BillingPeriod {
  months: number;
  label: string;
}

export const BILLING_PERIODS: Record<BillingPeriodId, BillingPeriod> = {
  y1: { months: 12, label: '1 year' },
  y2: { months: 25, label: '2 years + 1 month extra' },
  y3: { months: 38, label: '3 years + 2 months extra' },
  y4: { months: 51, label: '4 years + 3 months extra' },
};

export const PAID_PLANS: Record<PaidPlanId, PaidPlan> = {
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

export function getPaidPlan(plan: string): PaidPlan | null {
  if (plan === 'pro' || plan === 'elite') {
    return PAID_PLANS[plan];
  }
  return null;
}

export function getBillingPeriod(period: string): BillingPeriod | null {
  if (period === 'y1' || period === 'y2' || period === 'y3' || period === 'y4') {
    return BILLING_PERIODS[period];
  }
  return null;
}
