/// Labels, and the seed prices for a fresh database.
///
/// The live rupee amount is `paid_plan_catalog.amount_paise`. Orders and the
/// webhook do not charge from `amountPaise` here. Change a live price with
/// UPDATE on that table (see docs/06_PAYMENTS_PRODUCTION.md).
///
/// `amountPaise` / `durationDays` must still match the seed INSERT and
/// `checkout/paid_plans.js` so a new database starts at these prices.

export type PaidPlanId = 'pro' | 'elite';

export interface PaidPlan {
  amountPaise: number;
  currency: 'INR';
  durationDays: number;
  periodLabel: string;
  label: string;
  description: string;
}

export const PAID_PLANS: Record<PaidPlanId, PaidPlan> = {
  pro: {
    amountPaise: 149900,
    currency: 'INR',
    durationDays: 180,
    periodLabel: '6 months',
    label: 'Pro',
    description: '6 months of Pro',
  },
  elite: {
    amountPaise: 299900,
    currency: 'INR',
    durationDays: 365,
    periodLabel: '12 months',
    label: 'Elite',
    description: '12 months of Elite',
  },
};

export function getPaidPlan(plan: string): PaidPlan | null {
  if (plan === 'pro' || plan === 'elite') {
    return PAID_PLANS[plan];
  }
  return null;
}
