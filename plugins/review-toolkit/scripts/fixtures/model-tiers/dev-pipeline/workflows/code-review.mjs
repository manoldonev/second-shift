// Fixture: keys are unquoted so the guard's entry scans do not read the tier map as a
// dispatch table (the shipped engines carry the same shape and the same reason).
const DEFAULT_TIER_MAP = {
  reasoning: 'opus',
  code: 'sonnet',
  emit: 'haiku',
}

const REVIEWER_MODEL = {
  'security-reviewer': 'reasoning',
  'performance-reviewer': 'code',
}
