# Repository Invariants

- Inventory quantity is an audited financial ledger value. Do not expose manual stock increase or decrease controls in Inventory; stock entering the store must go through a Buy transaction, and stock leaving the store must go through a Sell transaction or an explicit audited correction flow.
- Product removal from Inventory must be a soft delete, not a hard delete. Keep product history available for audit and future deleted-item reports.
