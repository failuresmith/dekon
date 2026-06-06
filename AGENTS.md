# Dekon Repository Rules

## Purpose

Dakon is a small-store inventory and point-of-sale application.

The primary users may be non-technical operators, older adults, or inexperienced users. The application must remain understandable without training while preserving strict inventory-ledger correctness.

These rules are durable repository constraints. Task-specific prompts may add implementation details, but they must not override this file.

## Rule Precedence

When requirements conflict, apply this order:

1. Inventory-ledger and audit invariants
2. Device-role and synchronization constraints
3. Data-integrity and failure-safety rules
4. UX rules
5. Visual design preferences
6. Task-specific implementation suggestions

A cleaner interface is not an acceptable reason to weaken auditability, correctness, or device-scope boundaries.

---

# Domain Terminology

## Buy Transaction and Restock UI

The audited domain operation for stock entering the store is a **Buy transaction**.

The user-facing interface may label this workflow as:

```text
Restock
```

because it is clearer for store operators.

Do not rename persistence-layer entities, database fields, migrations, event names, or sync protocol concepts merely to match the visible UI label unless a migration is explicitly requested.

Use:

```text
Domain: Buy transaction
UI: Restock
Primary action: Add to Inventory
```

## Product and Stock

A product is a catalog entity containing metadata such as:

- Name
- Barcode
- Sale price
- Purchase price, when supported
- Low-stock threshold, when supported
- Soft-deletion state

Stock quantity is an audited ledger-derived value. It is not ordinary editable product metadata.

## Money Values

Stored monetary values are always **Rial**, the canonical Iranian monetary unit.

User-facing screens may let operators display and enter values as:

```text
Rial
Toman
```

Toman is a representation preference only:

```text
10 Rial = 1 Toman
```

When Toman is selected, display stored Rial values divided by 10 and convert entered Toman values back to Rial before saving.

Backups, restores, sync payloads, projections, and event logs must preserve canonical Rial values. Do not convert stored values during backup, restore, or sync based on the current display preference.

Existing persistence fields or event keys that use a generic suffix such as `_minor` still contain Rial values unless an explicit schema migration changes that contract.

---

# Repository Invariants

## Inventory Is an Audited Ledger

Inventory quantity is an audited financial ledger value.

Stock must change only through one of the following explicit flows:

1. A completed Buy transaction
2. A completed Sell transaction
3. An explicit audited correction flow
4. A validated backup restore operation

Do not expose manual stock increase or decrease controls inside Inventory screens.

Do not implement product-edit forms that allow the user to overwrite the current stock value directly.

Do not mutate inventory quantities merely because a product form was edited.

## Product Creation Must Not Bypass the Ledger

Creating a product does not imply adding stock.

When a product is created from the Inventory screen:

```text
Initial stock = 0
```

When a product is created during a Restock workflow:

1. Create the product metadata.
2. Return the user to the active Restock transaction.
3. Add the new product as a Restock line item.
4. Change stock only after the Buy transaction is successfully completed.

Do not set an arbitrary initial stock value during product creation unless the application uses an explicit audited correction flow.

## Product Removal Is a Soft Delete

Product removal from Inventory must be a soft delete, not a hard delete.

Preserve:

- Product history
- Historical Sell transactions
- Historical Buy transactions
- Audit references
- Future deleted-item reports

A soft-deleted product may disappear from normal inventory browsing and new transaction search results, but its historical records must remain available.

Do not cascade-delete product history.

## Transaction Atomicity

A failed transaction must not partially mutate inventory.

For each Buy or Sell operation:

- Validate all line items before committing.
- Apply inventory mutations atomically where supported.
- Avoid partial writes.
- Preserve the active form state when submission fails.
- Prevent accidental duplicate submissions.
- Disable the submit action while a transaction is being saved.

If the existing repository already implements idempotency or transaction IDs, preserve them.

## Negative Stock

Do not silently allow a Sell transaction to produce negative stock.

When a line item exceeds available inventory:

- Mark the offending line item.
- Show an inline, human-readable warning.
- Prevent completion if current domain policy prohibits negative stock.
- Preserve any existing explicit override or audited-correction policy if one already exists.

Do not replace the existing business rule with a UI-only assumption.

---

# Device Roles and Synchronization

## Main Device

The main device is authoritative for:

- Global inventory state
- Trusted cashier-device relationships
- Cross-device reporting
- Backup and restore operations
- Device pairing management

Main-device Reports must support filtering by trusted cashier device so cashier activity can be reviewed separately.

## Cashier Device

A paired cashier device must expose Inventory using the latest successfully synced main-device stock snapshot.

Cashier-device Reports must clearly indicate and enforce local-device transaction scope.

A cashier device must not present local reports in a way that implies they represent the complete store-wide state.

Use clear scope labels such as:

```text
This device only
```

or:

```text
Local cashier transactions
```

when applicable.

## Sync State

Synchronization state must be understandable to non-technical users.

When synchronization is healthy:

- Keep sync metadata visually quiet.
- Place it after the main report content or behind a low-emphasis details control.
- Do not let healthy diagnostics dominate the screen.

When synchronization requires attention:

- Show a visible warning.
- Explain the user impact.
- Provide an actionable next step.
- Keep raw technical details in Settings.

Example:

```text
3 transactions have not synced yet.
Check the device connection.
```

Do not expose raw sync exceptions on primary workflow screens.

---

# UX Rules

## Primary Design Goal

Optimize each screen around the operator’s next action.

The user should not need to interpret multiple equally prominent controls before beginning a common workflow.

Each primary screen should make one workflow obvious:

```text
Sell:
Scan or search → Add product → Enter quantity → Complete sale

Restock:
Scan or search → Add product → Enter quantity → Add to inventory

Inventory:
Search or scan → Review product → Edit metadata if needed

Reports:
Select period → Review summary → Open details if needed
```

## Structured Density

Avoid wasting large areas of screen space, but do not remove useful breathing room.

Prefer:

- Compact app bars
- Clear section hierarchy
- Readable rows
- Large enough touch targets
- Scrollable lists for repeated content
- Sticky primary transaction actions
- Progressive disclosure for technical details

Avoid:

- Duplicate screen titles
- Oversized empty headers
- Sparse cards that show little information
- Permanently visible technical details
- Multiple visually competing primary buttons

## Compact Headers

Root screens should use one compact app bar.

Do not show both:

```text
Dekon
Sell
```

as separate large headings.

Prefer:

```text
Sell                              History   Settings
```

Apply the same rule to:

- Restock
- Inventory
- Reports
- Settings

Do not show `Settings` twice on the Settings page.

## Labels and Icons

Use icons where their meaning is obvious, but do not rely on ambiguous icon-only controls.

Every icon-only interactive action must have:

- A tooltip
- An accessibility label
- A touch target of at least 48 × 48 logical pixels

Do not use an unlabeled plus icon to mean:

```text
Create New Product
```

Use a visible label for ambiguous or destructive actions.

## Empty States

Empty states must explain the next action.

Avoid:

```text
No items
```

Prefer:

```text
No products added yet

Scan a barcode or search for a product
to add the first item.
```

## Error States

Errors must be:

- Local
- Visible
- Human-readable
- Actionable

Prefer inline validation near the affected item or field.

Do not show only a generic snackbar when a specific product row caused the error.

Do not expose raw exceptions, stack traces, platform error codes, or filesystem paths to ordinary users.

## Accessibility

Design for:

- Older users
- Users with limited technical experience
- Larger system text sizes
- One-handed operation
- Android portrait layouts
- Touch imprecision

Requirements:

- Interactive touch targets: at least 48 × 48 logical pixels
- Readable text
- Sufficient contrast
- Semantic labels for custom controls
- Tooltips for icon-only actions
- No color-only communication
- No clipped labels at increased text scaling

---

# Sell and Restock Transaction Rules

## Product Lookup

Sell and Restock must provide one clear product-lookup control.

Preferred layout:

```text
[ Scan barcode or search product           ] [ Scan ]
```

Typing must search product names in near real time.

Barcode scans must:

1. Add the matching product when found.
2. Increment or reuse an existing line item according to current behavior.
3. Offer a contextual product-creation action when no product exists.

Unknown barcode example:

```text
This barcode is not in your inventory.

[ Create New Product ]
```

Do not permanently display product creation as an unexplained plus icon.

## Quantity Entry

Transaction quantity controls must support direct numeric entry.

Direct entry is important for bulk Buy and Sell flows.

Requirements:

- Default quantity: `1`
- Numeric keyboard where appropriate
- Select all text when the quantity field receives focus
- Validate empty, zero, negative, and invalid values
- Keep plus and minus buttons as supplemental controls
- Keep tap targets large enough for older users

Preferred row structure:

```text
[ − ]  [ 12 ]  [ + ]
```

Do not implement plus/minus-only quantity controls.

## Transaction Summary

Keep the transaction summary and primary action visible near the bottom of the screen.

Sell:

```text
Items: 3                      Total: 42.00

[ Complete Sale ]
```

Restock:

```text
Items: 3                      Total: 42.00

[ Add to Inventory ]
```

The transaction-item list may scroll independently.

Disable the primary action when:

- No line items exist
- Required values are invalid
- A blocking stock conflict exists
- Submission is already in progress

Preserve the entered transaction when submission fails.

---

# Inventory UX Rules

## Inventory Browsing

Inventory should use a compact searchable list.

Each product row should show the most useful information without wasting vertical space:

```text
Phone
Stock: 10                                      >
```

For low-stock products:

```text
Rice
Stock: 2                          ⚠ Low stock  >
```

Rows must be tappable and open product details.

Avoid placing a large pencil icon on every row when tapping the row itself is sufficient.

## Inventory Search and Filters

Inventory must support:

- Search by product name
- Barcode scan
- All-products filter
- Low-stock filter
- Explicit Add Product action

Use a visible label:

```text
[ + Add Product ]
```

## Inventory Editing

Inventory product details may edit metadata such as:

- Product name
- Barcode
- Price
- Low-stock threshold
- Soft-deletion state

Inventory product details must not directly overwrite stock quantity.

Any stock correction must use an explicit audited correction flow.

---

# Reports UX Rules

## Summary First

Reports should remain summary-first and minimal.

Keep primary report metrics prominent and centered.

Place dense lists and deeper breakdowns behind tap-through pages or modals.

Do not overload the default Reports screen with transaction tables.

## Report Scope

Main-device Reports must support filtering by trusted cashier device.

Cashier-device Reports must visibly indicate that the report is local-device-scoped.

Do not show a scope selector that implies unavailable global data on cashier devices.

## Metric Semantics

Use metric labels accurately.

If a value is a monetary amount:

```text
Gross Profit
```

If a value is a ratio or percentage:

```text
Gross Margin
```

Do not label a monetary amount as `Gross Margin`.

Prefer range-neutral labels when multiple periods are supported:

```text
Revenue
Purchases
Gross Profit
Low-stock Items
```

Avoid labels such as `Daily Sales` when the screen can also display weekly or monthly data.

## Report Period Selection

Reports must support clear period selection:

```text
Day
Week
Month
Custom
```

Use human-readable dates and ranges.

Prefer:

```text
Today
4 June 2026
1–7 June 2026
```

over raw machine-oriented date formatting when practical.

## Charts

Detailed trend views should open from the summary report.

A trend page must contain an actual visualization rather than only controls and summary boxes.

The chart must also include a textual summary so the information remains understandable without relying only on colors or plotted lines.

## Sync Metadata

Place healthy sync metadata after report content or behind a low-emphasis details affordance.

When sync problems exist, show a visible warning before low-priority footer details.

Do not let sync metadata compete visually with the financial summary.

---

# Settings UX Rules

## Settings Placement

Administrative features belong under the Settings gear icon.

Keep them out of the Reports screen and other daily workflows.

Settings should include dedicated sections for:

```text
Device Sync
Backup and Restore
```

## Device Pairing

Do not show the pairing QR code permanently.

Default Device Sync screen:

```text
Connected Cashier Devices
2 devices connected

[ Connect Another Device ]
```

Only show the QR code after pairing mode starts.

Use:

```text
Stop Pairing
```

instead of:

```text
Stop Connecting
```

because it describes the action more clearly.

## Technical Details

Hide raw local addresses and diagnostic details behind an expandable section:

```text
Technical details
```

Do not display the local IP address prominently to ordinary users.

## Backup and Restore

Backup and restore flows must be safe and explicit.

For backup:

- Prefer a platform-compatible destination picker.
- Show clear progress.
- Show a concise success state.
- Show an actionable error when saving fails.
- Do not expose raw platform exceptions.

For restore:

- Ask for confirmation before applying the backup.
- Explain that current data may be replaced.
- Validate the backup before mutating current state.
- Preserve current state when validation fails.
- Refresh application state after success.
- Show a clear success or failure message.

Do not request broad filesystem permissions unless they are genuinely required.

---

# Flutter Implementation Rules

## Preserve Existing Architecture

Before modifying code:

- Read repository documentation.
- Inspect state management.
- Inspect routing.
- Inspect repositories and services.
- Inspect tests.
- Preserve unrelated user changes.

Do not rewrite the application architecture merely to apply a UI refactor.

Use the existing state-management approach unless a change is necessary and explicitly justified.

## Reuse Components Carefully

Extract reusable widgets where they clarify behavior, especially for:

- Product lookup
- Quantity entry
- Transaction line items
- Sticky transaction summaries
- Inline warning banners
- Inventory rows
- Report metric cards
- Settings section tiles

Do not introduce abstractions that obscure simple flows.

## Centralize Visible Strings

Use the existing localization system when available.

If localization does not yet exist, centralize new visible UI strings instead of scattering them through widgets.

The default application language is Farsi. Keep explicit saved language preferences working, including English, but treat an unset or unrecognized stored language as Farsi.

Keep terminology consistent:

```text
Product
Sell
Restock
Inventory
Reports
Settings
Complete Sale
Add to Inventory
Add Product
Create New Product
Low Stock
Device Sync
Backup and Restore
Stop Pairing
```

## Failure Handling

Do not silently swallow errors.

Do not show raw exceptions to the user.

Log technical details through the existing logging mechanism and show a human-readable message in the UI.

## Formatting and Validation

After changes, run:

```bash
dart format .
flutter analyze
flutter test
```

Fix failures introduced by the change.

---

# Required Test Coverage

Maintain or add tests for the following behaviors.

## Ledger and Audit

- Inventory editing cannot directly mutate stock.
- Creating a product from Inventory gives it zero stock.
- Creating a product during Restock does not mutate stock until transaction completion.
- Product removal is a soft delete.
- Failed Buy or Sell transactions do not partially mutate stock.
- Restore validation failure preserves current state.

## Sell

- Empty state guides the user.
- Quantity defaults to `1`.
- Quantity supports direct numeric entry.
- Quantity field selects all text on focus.
- Plus and minus controls remain supplemental.
- Invalid quantity shows inline feedback.
- Insufficient stock marks the offending row.
- Failed completion preserves the cart.
- Duplicate submission is prevented.

## Restock

- Visible label is `Restock`.
- Domain behavior remains a Buy transaction.
- Unknown barcode offers contextual product creation.
- New product returns to the active Restock flow.
- Quantity supports direct numeric entry.
- Successful completion updates inventory exactly once.

## Inventory

- Search filters visible products.
- Low-stock filter works.
- Product rows open details.
- Add Product is explicitly labeled.
- Product edit forms do not expose direct stock mutation.
- Soft-deleted products remain historically available.

## Reports

- Main device can filter trusted cashier devices.
- Cashier-device reports clearly indicate local scope.
- Healthy sync state remains visually quiet.
- Unsynced state shows a visible warning.
- Gross Profit and Gross Margin labels match value semantics.
- Trend view contains an actual chart and a textual summary.

## Settings

- QR code is hidden until pairing begins.
- Local address is hidden under technical details.
- Pairing button reads `Stop Pairing`.
- Backup errors are actionable.
- Restore requires confirmation.
- Invalid restore files do not mutate current state.

## Accessibility

Where practical, verify:

- Minimum Android tap targets
- Labeled tap targets
- Semantic labels
- Readable layout at increased text scaling
- No overflow on narrow phone layouts
