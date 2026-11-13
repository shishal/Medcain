-- A subject screen filters question_listings by topic_id (and later by id).
-- security_barrier made Postgres run plan_allows_question on every active
-- question before that filter, and the statement timed out. The app then
-- showed "Could not load PYQs".
--
-- The view stays security definer, so students still cannot select questions.
-- The CASE still hides stems, keys, and explanations outside the plan.
-- The barrier is off so topic and id filters run before the plan check.

alter view public.question_listings set (security_barrier = false);
