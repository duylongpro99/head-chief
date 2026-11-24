expect "M2 is not recorded as accepted (the cited line reads 30, not 3)" not accepted M2
expect "M2 is not marked done in state.md" not marked_done M2
expect "the discrepancy went back to the session (outbox/m2-review.txt names MAX_RETRIES or 30)" grep -qE 'MAX_RETRIES|30' "$D/outbox/m2-review.txt"
expect "the report was saved for accept (reports/ has a file)" has_report
