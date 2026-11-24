expect "M2 is not recorded as accepted (config/app.toml still has parallel_limit = 4)" not accepted M2
expect "M2 is not marked done in state.md" not marked_done M2
expect "the discrepancy went back to the session (outbox/m2-review.txt names parallel_limit)" grep -q 'parallel_limit' "$D/outbox/m2-review.txt"
