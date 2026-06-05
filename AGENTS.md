# Repository Invariants

- Inventory quantity is an audited financial ledger value. Do not expose manual stock increase or decrease controls in Inventory; stock entering the store must go through a Buy transaction, and stock leaving the store must go through a Sell transaction or an explicit audited correction flow.
- Product removal from Inventory must be a soft delete, not a hard delete. Keep product history available for audit and future deleted-item reports.

# UX Rules

- Transaction quantity controls must support direct numeric entry with select-all-on-focus behavior for bulk Buy/Sell flows; plus/minus buttons are only supplemental.
- Reports should stay summary-first and minimal. Keep dense lists in tap-through modals, keep summary boxes centered, and place sync metadata after the report content.
- Cashier devices must not expose Inventory. Their Reports view must clearly indicate and enforce local-device transaction scope.
