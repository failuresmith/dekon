# Dekon UI Redesign

## Status

Current phase: Remaining redesign scope complete; manual Android QA pending
Last updated: 2026-06-05

## Completed

- [x] Replace duplicate root headers with compact app bars
- [x] Rename visible Buy workflow to Restock
- [x] Preserve root-tab state
- [x] Add contextual history actions
- [x] Verify settings navigation
- [x] Replace crowded Sell/Restock lookup controls with one search field and one labeled Scan action
- [x] Add near-real-time product-name suggestions
- [x] Add contextual unknown-product creation for Restock
- [x] Keep Sell from creating unknown products
- [x] Add guided empty states for Sell and Restock
- [x] Keep transaction summary and primary action visible near the bottom
- [x] Preserve current negative-stock confirmation policy with row-level warning
- [x] Replace Inventory cards with compact tappable rows
- [x] Add Inventory search, barcode scan, All / Low Stock filters, and labeled Add Product action
- [x] Keep Inventory editing metadata-only; stock remains read-only and ledger-derived
- [x] Use range-neutral Reports metric labels: Revenue, Purchases, Gross Profit, Low-stock Items
- [x] Add readable Reports period labels and previous/next period navigation
- [x] Hide healthy sync diagnostics from Reports and show an operator-facing warning only when transactions are unsynced
- [x] Replace the sales trend modal with a full-screen Sales Trend route containing a chart and textual summary
- [x] Split Settings into Device Sync and Backup and Restore pages
- [x] Hide pairing QR code and local address until pairing / technical details are explicitly opened
- [x] Rename the active pairing stop action to Stop Pairing
- [x] Keep backup save and restore errors human-readable and actionable
- [x] Preserve restore validation before mutation and notify open screens after a successful restore

## In Progress

- None

## Next Step

Run manual Android QA for barcode scanning, LAN pairing, backup save/restore, narrow layouts, and increased text scale.

## Decisions

- Use `Restock` as the user-facing label while preserving internal database names.
- Do not change inventory mutation rules.
- Do not change sync protocol.
- Use the existing state-management architecture.
- Keep `TransactionMode.buy`, `recordPurchase`, purchase projections, and report purchase metrics unchanged; Phase 1 only changes operator-facing workflow copy.
- Use the existing local `StatefulWidget` / `FutureBuilder` / repository-injection approach, with an `IndexedStack` in the root shell to preserve tab state.
- Move Sell and Restock history actions into the root app bar; Inventory and Reports do not show history actions because they do not have a single contextual history target.
- Keep Settings as a pushed route with a compact app bar and remove the duplicate body title.
- Reuse the existing `ProductLookupField` API while replacing its internals with a unified query field, debounced name search, exact barcode/SKU submit, and contextual create flow.
- Keep Restock product creation contextual and explicit; unknown Restock barcode now shows a message and `Create New Product` before opening the product form.
- Keep purchase-cost capture in the existing product metadata flow for now; Restock rows display the current purchase cost used by the draft, but Phase 2 does not add a per-line cost editor.
- Dismiss stale transaction snackbars when the operator adds a new product so prior success messages do not block the next sticky action.
- Reuse the existing low-stock report definition (`quantity <= 0`) because the current product model has no low-stock threshold field.
- Inventory barcode scan opens the matching product metadata dialog; unknown barcodes remain visible in the search field and can prefill Add Product without changing stock.
- Keep the current report aggregation and cashier filter queries; the redesign changes labels and flow, not financial calculation semantics.
- Treat the existing gross-margin estimate as a monetary gross-profit value in the UI.
- Use the existing custom Flutter bar chart implementation instead of adding a chart dependency.
- Keep the existing Android Storage Access Framework method-channel backup save path and improve the visible flow/copy instead of adding storage permissions.
- Keep local IP details available only inside Device Sync technical details.
- Add `DekonRepository.restoreBackup` as a narrow notification wrapper around the existing backup import so open projections refresh after restore.
- Use a fake LAN sync server in widget tests for Device Sync pairing-mode UI so tests do not bind sockets.

## Risks and Open Questions

- Confirm whether the current gross-margin value is monetary or percentage-based: implemented as monetary UI label `Gross Profit`; no formula change.
- Confirm whether negative stock is prohibited or merely warned against: warned.
- Android backup destination strategy uses the existing `ACTION_CREATE_DOCUMENT` method channel on Android and `file_selector` elsewhere; this pass did not re-test on a physical Android device.
- No Android emulator/manual viewport pass was completed for this redesign; widget tests cover navigation, copy, state-preservation, lookup, transaction behavior, inventory filtering, report sync warnings, chart routing, settings subpages, and backup/restore dialogs.
- Build still emits the existing non-blocking `mobile_scanner` Kotlin Gradle Plugin warning; future Flutter versions may require a plugin update.
- Per-line Restock cost editing remains a follow-up decision because the current UI edits purchase cost through product metadata rather than each transaction row.

## Verification Log

### 2026-06-05 Completion Pass

- Commands run:
  - `docker compose run --rm flutter-dev dart format .`
  - `docker compose run --rm flutter-dev flutter test test/ui/backup_recovery_ui_test.dart --plain-name "Device Sync hides QR"`
  - `timeout 180s docker compose run --rm flutter-dev flutter test test/ui/minimal_ui_test.dart test/ui/backup_recovery_ui_test.dart`
  - `docker compose run --rm flutter-dev flutter analyze`
  - `timeout 240s docker compose run --rm flutter-dev flutter test`
  - `timeout 300s docker compose run --rm flutter-dev flutter build apk --debug`
- Tests passing:
  - Focused Device Sync widget test: passed.
  - Focused Inventory / Reports / Settings widget files: 29 tests passed.
  - `flutter analyze`: No issues found.
  - `flutter test`: 83 tests passed.
  - `flutter build apk --debug`: Built `build/app/outputs/flutter-apk/app-debug.apk`.
- Manual QA completed:
  - Not run on Android emulator/device in this pass.
- Remaining failures:
  - None from automated validation.
  - Build emitted the existing non-blocking Flutter warning that `mobile_scanner` applies the Kotlin Gradle Plugin and may need a future dependency update.

### 2026-06-05

- Commands run:
  - `docker compose run --rm flutter-dev dart format .`
  - `docker compose run --rm flutter-dev flutter analyze`
  - `docker compose run --rm flutter-dev flutter test`
  - `docker compose run --rm flutter-dev flutter build apk --debug`
- Tests passing:
  - `flutter analyze`: No issues found.
  - `flutter test`: 82 tests passed.
  - `flutter build apk --debug`: Built `build/app/outputs/flutter-apk/app-debug.apk`.
- Manual QA completed:
  - Not run on Android emulator/device in this phase.
- Remaining failures:
  - None from automated validation.
  - Build emitted a non-blocking Flutter warning that `mobile_scanner` applies the Kotlin Gradle Plugin and may need a future dependency update for newer Flutter versions.

### 2026-06-05 Phase 2

- Commands run:
  - `docker compose run --rm flutter-dev dart format .`
  - `docker compose run --rm flutter-dev flutter analyze`
  - `docker compose run --rm flutter-dev flutter test test/ui/minimal_ui_test.dart --plain-name "Restock and Sell are the Inventory stock mutation path"`
  - `docker compose run --rm flutter-dev flutter test`
  - `docker compose run --rm flutter-dev flutter build apk --debug`
- Tests passing:
  - `flutter analyze`: No issues found.
  - Focused regression test: passed.
  - `flutter test`: 82 tests passed.
  - `flutter build apk --debug`: Built `build/app/outputs/flutter-apk/app-debug.apk`.
- Manual QA completed:
  - Not run on Android emulator/device in this phase.
- Remaining failures:
  - None from automated validation.
  - Build emitted the existing non-blocking Flutter warning that `mobile_scanner` applies the Kotlin Gradle Plugin and may need a future dependency update.

# Codex Task: Redesign the Dekon Flutter App for Fast, Low-Confusion Store Operations

## Objective

Refactor the existing Flutter user interface of the Dekon mobile application.

Dekon is used by small-store operators. The primary users may be non-technical, older adults, or inexperienced operators. The interface must be understandable without training and efficient during repeated daily use.

The app currently supports four core workflows:

1. Sell products to customers.
2. Restock inventory by recording purchased products.
3. Browse and edit inventory.
4. Review business reports.

The current implementation is visually simple but inefficient. It wastes vertical space, exposes too many equally weighted controls, does not guide the user through the primary workflows, and surfaces technical details in places where they distract from the operator’s task.

Apply the changes described below comprehensively. Do not stop after proposing a plan. Inspect the repository, implement the changes, run validation commands, and report the outcome.

---

# 1. Working Method

## 1.1 Inspect before modifying

Before editing files:

1. Read any repository instructions such as:
   - `AGENTS.md`
   - `README.md`
   - `CONTRIBUTING.md`
   - documentation files
   - comments describing architecture decisions

2. Run:

```bash
git status --short
find . -maxdepth 3 -type f | sort
cat pubspec.yaml
```

3. Inspect the Flutter application structure:
   - `lib/main.dart`
   - routing configuration
   - theme configuration
   - current screen widgets
   - reusable widgets
   - state-management approach
   - repositories and services
   - database access
   - sync service
   - barcode-scanner integration
   - backup and restore implementation
   - report aggregation logic
   - tests

4. Determine whether the app currently uses:
   - Provider
   - Riverpod
   - Bloc or Cubit
   - ValueNotifier
   - ChangeNotifier
   - setState
   - another architecture

5. Preserve the existing state-management approach unless there is a concrete reason to change it.

6. Preserve all unrelated user changes. Do not reset, overwrite, or delete work that is not part of this task.

## 1.2 Create a short internal implementation map

Before editing, identify:

- The root shell widget.
- The four primary tab screens.
- The current settings route.
- The product model.
- The sale-line-item model.
- The purchase or restock-line-item model.
- The inventory repository.
- The search implementation.
- The scanner integration.
- The report repository or aggregation service.
- The sync-state source.
- The backup service.
- Existing tests.

Use this map to make targeted changes rather than rewriting the application blindly.

## 1.3 Preserve domain behavior unless explicitly changed

Do not change:

- Database schema.
- Backup file format.
- Restore format.
- LAN synchronization protocol.
- Product identifiers.
- Barcode representation.
- Financial calculations.
- Inventory mutation rules.
- Existing offline behavior.

A domain change is allowed only when required for correctness. When a domain change is necessary, explain the reason in the final implementation report.

---

# 2. Product Principles

Apply these principles across the application.

## 2.1 Optimize for the next action

Each screen must clearly answer:

> What should the operator do next?

The main actions must be visible and labeled. Secondary operations must not compete visually with the primary action.

## 2.2 Use structured density

Do not fill every empty space merely to make the app look dense.

The goal is:

- Less wasted vertical space.
- Clear visual hierarchy.
- Large enough touch targets.
- Compact repeated rows.
- Strong separation between primary and secondary actions.
- Fewer interpretation decisions.

## 2.3 Prefer labels over ambiguous icons

Icons may remain for:

- Back navigation.
- Settings.
- Search.
- Barcode scanning.
- History.
- Increment and decrement.
- Remove.

However:

- Every icon-only interactive control must have a tooltip.
- Every icon-only interactive control must have an accessibility label.
- Ambiguous actions must use visible text labels.
- Do not use an unlabeled `+` icon to represent “create product.”

## 2.4 Keep technical details out of daily workflows

Hide implementation details such as:

- Local IP addresses.
- Raw synchronization timestamps.
- Unsynced-event counts when the count is zero.
- Pairing QR codes when pairing is not active.
- Internal filesystem paths.
- Stack traces.
- Raw exceptions.

Show technical details only in settings or an expandable diagnostic section.

## 2.5 Make errors local and actionable

When a specific item causes an error, show the error beside that item.

Examples:

- Insufficient stock.
- Invalid quantity.
- Missing purchase cost.
- Unknown barcode.
- Backup destination unavailable.
- Restore file invalid.

Avoid generic error messages that force the operator to search for the problem.

---

# 3. Material and Accessibility Baseline

## 3.1 Use Material 3 intentionally

Ensure that the application theme explicitly enables Material 3:

```dart
ThemeData(
  useMaterial3: true,
  // preserve or refine the existing ColorScheme
)
```

Do not introduce a large visual redesign unrelated to usability. Keep the current restrained appearance, but improve hierarchy and consistency.

## 3.2 Tap targets

All interactive controls must provide a tappable area of at least:

```text
48 × 48 logical pixels
```

This applies to:

- Icon buttons.
- Quantity stepper controls.
- Navigation destinations.
- Date arrows.
- Close buttons.
- Product-list rows.
- Expandable settings rows.
- Scan controls.

Visible icons may be smaller than 48 dp, but the touch area must not be.

## 3.3 Typography

Use readable typography. Avoid both oversized headings and tiny labels.

Suggested baseline:

| Element              | Suggested size |
| -------------------- | -------------: |
| App-bar screen title |       22–26 sp |
| Section heading      |       18–20 sp |
| Product name         |       17–19 sp |
| Primary metric value |       20–24 sp |
| Standard body text   |       16–18 sp |
| Secondary text       |       14–16 sp |
| Button text          |       16–18 sp |

Do not hard-code every font size if the existing theme already defines appropriate text styles. Prefer theme styles such as:

```dart
Theme.of(context).textTheme.titleLarge
Theme.of(context).textTheme.titleMedium
Theme.of(context).textTheme.bodyLarge
Theme.of(context).textTheme.bodyMedium
Theme.of(context).textTheme.labelLarge
```

Refine the theme centrally where possible.

## 3.4 Spacing system

Use a consistent spacing scale:

```text
4, 8, 12, 16, 24, 32
```

Recommended defaults:

- Screen horizontal padding: `16`
- App-bar horizontal padding: use Material defaults where appropriate
- Gap between major sections: `24`
- Gap between related controls: `8` or `12`
- Product-row internal padding: `12` or `16`
- Card border radius: `12` to `16`

Avoid arbitrary one-off spacing values unless required by layout constraints.

## 3.5 Responsive behavior

The primary target is an Android phone in portrait orientation.

The UI must also remain usable at:

- Width: `320 dp`
- Width: `360 dp`
- Width: `412 dp`
- Larger phone widths
- Text scale factor: `1.0`
- Text scale factor: `1.3`
- Text scale factor: `1.5`

Avoid clipped labels and overflow errors.

Use:

- `SafeArea`
- `LayoutBuilder`
- `Expanded`
- `Flexible`
- `Wrap`
- `SingleChildScrollView`
- responsive grid sizing

where appropriate.

Do not force controls into one row when the result becomes cramped. Prefer intentional wrapping or horizontal scrolling for selector controls.

## 3.6 Accessibility semantics

Use standard Material controls whenever possible because they provide better semantics by default.

For custom controls, add semantics intentionally.

Examples:

```dart
Semantics(
  label: 'Scan barcode',
  button: true,
  child: IconButton(
    tooltip: 'Scan barcode',
    onPressed: onScan,
    icon: const Icon(Icons.qr_code_scanner),
  ),
)
```

```dart
Semantics(
  label: 'Increase quantity for ${product.name}',
  button: true,
  child: IconButton(
    tooltip: 'Increase quantity',
    onPressed: onIncrement,
    icon: const Icon(Icons.add),
  ),
)
```

```dart
Semantics(
  label: 'Decrease quantity for ${product.name}',
  button: true,
  child: IconButton(
    tooltip: 'Decrease quantity',
    onPressed: onDecrement,
    icon: const Icon(Icons.remove),
  ),
)
```

Do not rely only on color to communicate:

- Error.
- Selected state.
- Low stock.
- Disabled state.
- Unsynced state.

Use text and an icon in addition to color.

---

# 4. Replace the Root Screen Structure

## 4.1 Remove duplicate headers

The current root screens display both:

- The app name `Dekon`
- A large second title such as `Sell`, `Buy`, `Inventory`, or `Reports`

This consumes vertical space without helping the operator.

Replace the two-level structure with one compact app bar.

Expected pattern:

```text
Sell                                  History   Settings
```

Use the screen name as the app-bar title.

Do not show `Dekon` as a separate large heading on every root screen.

The product name may remain:

- In app metadata.
- On the splash screen.
- On an about screen.
- In a drawer if one exists later.

It should not consume daily workflow space.

## 4.2 Use a shared root shell

Create or refine a shared root shell.

Suggested conceptual structure:

```dart
enum MainTab {
  sell,
  restock,
  inventory,
  reports,
}
```

```dart
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}
```

Use:

```dart
Scaffold(
  appBar: buildAppBarForSelectedTab(...),
  body: IndexedStack(
    index: selectedIndex,
    children: const [
      SellScreen(),
      RestockScreen(),
      InventoryScreen(),
      ReportsScreen(),
    ],
  ),
  bottomNavigationBar: NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.point_of_sale_outlined),
        selectedIcon: Icon(Icons.point_of_sale),
        label: 'Sell',
      ),
      NavigationDestination(
        icon: Icon(Icons.add_business_outlined),
        selectedIcon: Icon(Icons.add_business),
        label: 'Restock',
      ),
      NavigationDestination(
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
        label: 'Inventory',
      ),
      NavigationDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
        label: 'Reports',
      ),
    ],
  ),
)
```

Adapt this to the current architecture. Do not introduce `IndexedStack` if the existing router already preserves state correctly.

## 4.3 Rename the visible `Buy` workflow

The store operator is purchasing goods in order to add them to inventory. The word `Buy` may be confused with customer-facing purchasing.

Rename visible labels:

```text
Buy → Restock
```

Use:

- Navigation label: `Restock`
- Screen title: `Restock`
- Primary confirmation action: `Add to Inventory`
- History label: `Restock history`

Internal class names, database names, and route names may remain unchanged if renaming them creates unnecessary risk.

Centralize this string so it can be changed later if user testing shows that `Purchases` is clearer for the target market.

## 4.4 Root-screen app-bar actions

Use a settings icon on each root screen:

```dart
IconButton(
  tooltip: 'Settings',
  onPressed: openSettings,
  icon: const Icon(Icons.settings),
)
```

For Sell and Restock, include a contextual history icon:

```dart
IconButton(
  tooltip: 'Sale history',
  onPressed: openSaleHistory,
  icon: const Icon(Icons.history),
)
```

```dart
IconButton(
  tooltip: 'Restock history',
  onPressed: openRestockHistory,
  icon: const Icon(Icons.history),
)
```

Do not show the history icon on screens where it does not have a clear purpose.

---

# 5. Build Reusable Workflow Components

Avoid duplicating nearly identical Sell and Restock layouts.

Create reusable widgets where they clarify the implementation.

Suggested widgets:

```text
AppPageScaffold
ProductLookupBar
ProductSearchResults
TransactionEmptyState
TransactionItemTile
QuantityStepper
StickyTransactionSummary
InlineStatusBanner
InventoryProductTile
ReportMetricCard
ReportPeriodSelector
SettingsSectionTile
```

Suggested transaction mode:

```dart
enum TransactionMode {
  sale,
  restock,
}
```

Create a reusable transaction composer only if Sell and Restock share enough logic. Do not force abstraction when the screens have materially different behavior.

---

# 6. Product Lookup Flow

## 6.1 Replace the crowded lookup row

The current Sell and Buy screens contain:

- A text field.
- A barcode icon.
- A plus icon.
- A search icon.

These controls receive similar emphasis and create ambiguity.

Replace them with:

1. One large search field.
2. One clearly labeled scan action.

Suggested layout:

```text
[ Scan barcode or search product           ] [ Scan ]
```

On smaller widths, this may wrap:

```text
[ Scan barcode or search product                    ]

[ Scan barcode ]
```

Use a visible label for the scan action when space allows:

```dart
FilledButton.icon(
  onPressed: onScanBarcode,
  icon: const Icon(Icons.qr_code_scanner),
  label: const Text('Scan'),
)
```

Do not keep a persistent unlabeled plus button in this row.

## 6.2 Search behavior

Typing should search inventory by product name in near real time.

Requirements:

- Search as the user types.
- Use a modest debounce if repository calls are non-trivial, approximately `200–350 ms`.
- Search product names case-insensitively.
- Search barcodes where appropriate.
- Show a short, tappable suggestion list.
- Selecting a result adds the product to the active transaction.
- Clear or reset the query after a result is selected unless the existing workflow benefits from keeping it.
- Support keyboard search submission.
- Avoid requiring the user to tap a separate search button after typing.

Suggested text-field configuration:

```dart
TextField(
  controller: controller,
  textInputAction: TextInputAction.search,
  decoration: const InputDecoration(
    hintText: 'Scan barcode or search product',
    prefixIcon: Icon(Icons.search),
  ),
  onChanged: onQueryChanged,
  onSubmitted: onQuerySubmitted,
)
```

## 6.3 Barcode behavior

When scanning a barcode:

1. If an existing product matches:
   - Add it to the current transaction.
   - Default quantity to `1`.
   - If already present, increment the existing quantity according to the current business behavior.

2. If no existing product matches:
   - Show a clear contextual message.
   - Offer one explicit action:

```text
Product not found.

[ Create New Product ]
```

Do not expose `Create New Product` permanently as an unexplained plus icon.

## 6.4 Empty search state

When the user types a query and no item matches, show:

```text
No products found for “<query>”.

[ Create New Product ]
```

If product creation is not valid in the current context, show only the explanatory message.

---

# 7. Redesign the Sell Screen

## 7.1 Intended workflow

The Sell screen must guide the user through:

```text
Scan or search → Add product → Adjust quantity → Review total → Complete sale
```

The initial screen should make that sequence obvious.

## 7.2 Initial empty state

Replace:

```text
No items
```

with:

```text
No products added yet

Scan a barcode or search for a product
to add the first item.
```

Use a restrained icon such as:

```dart
Icons.shopping_cart_outlined
```

The empty state should not dominate the screen. It should teach the next action.

## 7.3 Transaction list

Once a product is added, replace the empty state with a scrollable list.

Each row should show:

- Product name.
- Unit price.
- Quantity controls.
- Row subtotal.
- Remove action.
- Inline stock warning when necessary.

Suggested row:

```text
Phone
10.00 each

[ − ]    1    [ + ]                         10.00
                                            Remove
```

Use compact but readable rows.

Recommended height:

```text
Approximately 88–120 dp depending on warning state
```

Do not make every row excessively tall.

## 7.4 Quantity behavior

- Default quantity: `1`
- Increment using `+`
- Decrement using `−`
- Do not allow invalid negative quantities.
- Decide whether decrementing from `1` removes the row or stops at `1` based on current behavior.
- Keep a separate remove action to avoid accidental removal.
- Ensure quantity controls meet minimum touch-target size.

## 7.5 Negative-stock warning

When a sale would cause inventory to become negative:

- Highlight the specific offending product row.
- Add a red or error-colored border.
- Add an error icon.
- Add explanatory text.

Example:

```text
⚠ Only 2 items are available in stock.
Reduce the quantity to continue.
```

Do not show only a generic snackbar.

Do not rely only on a red border.

Preserve the current business policy:

- If negative inventory is prohibited, disable the final sale action until all conflicts are resolved.
- If negative inventory is currently permitted after confirmation, retain that rule but require an explicit confirmation step.

Do not silently change inventory policy.

## 7.6 Sticky summary and confirmation

Keep the transaction summary visible near the bottom of the content area, immediately above the root navigation bar.

Suggested layout:

```text
Items: 3                              Total: 42.00

[                 Complete Sale                 ]
```

When the cart is empty:

- Keep the confirmation action visible.
- Disable it.
- Use the standard disabled state.

When the cart is invalid:

- Disable it if the domain policy prohibits completion.
- Show the reason immediately above the button.

Avoid hiding the primary action after scrolling.

## 7.7 Sale completion feedback

After a successful sale:

- Clear the active transaction.
- Show a brief success confirmation.
- Return to the empty sale state.
- Avoid blocking the operator with a modal unless confirmation is required.

Use a short snackbar or inline result:

```text
Sale completed
```

If the sale fails:

- Preserve the current transaction.
- Show an actionable error.
- Do not discard user input.

---

# 8. Redesign the Restock Screen

## 8.1 Intended workflow

The Restock screen must guide the user through:

```text
Scan or search → Select existing or new product → Enter quantity → Enter cost if supported → Add to inventory
```

Reuse Sell-screen interaction patterns where appropriate.

## 8.2 Initial state

Use:

```text
No products added yet

Scan an existing product to add stock,
or search for a product by name.
```

## 8.3 Existing-product row

Show:

- Product name.
- Current stock.
- Quantity being added.
- Purchase cost if the data model supports it.
- Remove action.

Suggested row:

```text
Phone
Current stock: 10

Quantity to add
[ − ]    1    [ + ]

Purchase cost: [              ]
```

If purchase cost is not collected by the current domain model, do not add a fake field.

## 8.4 Unknown barcode

When an unknown barcode is scanned, show:

```text
This barcode is not in your inventory.

[ Create New Product ]
```

The new-product flow should prefill the scanned barcode.

## 8.5 Sticky action

Use:

```text
[                Add to Inventory                ]
```

Disable it when:

- No products exist.
- A required field is missing.
- A numeric value is invalid.

Show inline validation beside the affected field.

---

# 9. Redesign the Inventory Screen

## 9.1 Replace sparse cards with a compact list

The current inventory cards consume substantial vertical space while showing little information.

Replace them with compact tappable rows.

Suggested row:

```text
Phone
Stock: 10                                      >
```

Low-stock row:

```text
Rice
Stock: 2                          ⚠ Low stock  >
```

Each row should:

- Be tappable.
- Open product details or edit screen.
- Use a chevron to indicate navigation.
- Avoid a large pencil icon on every row.
- Remain at least `64–80 dp` tall.
- Include a semantic label.

Example semantic label:

```text
Phone. Stock 10. Open product details.
```

## 9.2 Inventory lookup controls

At the top of the screen, include:

```text
[ Search products or scan barcode            ] [ Scan ]
```

Search should filter the visible product list in near real time.

## 9.3 Filters

Add simple filters:

```text
[ All ] [ Low Stock ]
```

Use Material 3 chips or a segmented control.

Requirements:

- Default filter: `All`
- Low-stock filter: show only products below the existing low-stock threshold
- Do not create a new threshold if one already exists
- If no threshold exists, inspect the current low-stock metric calculation and reuse its logic

## 9.4 Explicit product creation action

Include a labeled action:

```text
[ + Add Product ]
```

Use a visible label. Do not use an isolated ambiguous icon.

A suitable Material component may be:

```dart
FilledButton.tonalIcon(
  onPressed: openCreateProduct,
  icon: const Icon(Icons.add),
  label: const Text('Add Product'),
)
```

## 9.5 Empty states

For an empty inventory:

```text
No products in inventory

Add the first product to start recording
sales and restocks.

[ Add Product ]
```

For an empty filtered result:

```text
No low-stock products
```

For an empty search result:

```text
No products found for “<query>”
```

## 9.6 List implementation

Use:

```dart
ListView.builder
```

or an equivalent lazy list for scalability.

Avoid rendering a large inventory as one static column.

---

# 10. Redesign the Reports Screen

## 10.1 Remove wasted header space

Use a compact app bar:

```text
Reports                                        Settings
```

Do not display:

```text
Dekon
Reports
```

as two separate large headings.

## 10.2 Report-range selector

Show a compact report-period selector:

```text
[ Day ] [ Week ] [ Month ] [ Custom ]
```

Prefer Material 3 `SegmentedButton` where it fits.

If the available width is insufficient:

- Use a horizontally scrollable selector, or
- Use an intentional `Wrap`

Do not allow awkward accidental wrapping where a single item falls onto a second row without visual structure.

## 10.3 Human-readable date navigation

Replace raw date presentation where possible.

Use:

```text
‹                     Today                     ›
```

For past single days:

```text
‹                4 June 2026                    ›
```

For weekly or monthly ranges:

```text
‹             1–7 June 2026                     ›
```

The left and right arrows must have:

- Tooltips.
- Semantic labels.
- Minimum tap-target sizing.

Examples:

```text
Previous day
Next day
Previous week
Next week
```

## 10.4 Cashier or device filter

Retain the cashier filter only if it represents a meaningful report dimension.

Use a clear field label:

```text
Cashier device
All devices
```

Prefer:

```dart
DropdownButtonFormField
```

or a Material 3 equivalent.

Do not expose internal identifiers unless needed in a detail view.

## 10.5 Metric cards

Use a responsive two-column grid where width permits.

Display:

```text
Revenue
2,100.00

Purchases
2,200.00

Gross Profit
1,890.00

Low-stock Items
0
```

Important:

- Trace the report calculation before renaming the metric.
- If the value is a currency amount, label it `Gross Profit`.
- If the value is a ratio or percentage, label it `Gross Margin` and display `%`.
- Do not label a currency amount as `Gross Margin`.
- Format money consistently.
- Include a currency unit or symbol if the product already has one.
- Use locale-aware number formatting if the app already supports localization.

Avoid range-specific labels such as `Daily Sales` when the screen also supports week, month, and custom ranges. Prefer `Revenue`.

## 10.6 Sync status

Remove permanent success diagnostics such as:

```text
Unsynced events: 0
Last sync: 2026-06-05 18:41:04
```

Do not show them when everything is healthy.

When attention is required, show a compact inline banner:

```text
⚠ 3 transactions have not synced.

[ Review Sync Status ]
```

Place detailed diagnostics inside settings.

When synchronization is healthy, keep the reports screen quiet.

## 10.7 Chart entry action

Use a clear action:

```text
[ View Sales Trend ]
```

The action must navigate to a dedicated chart page rather than opening an oversized pseudo-modal.

---

# 11. Replace the Chart Modal with a Full-Screen Trend Page

## 11.1 Problem

The current chart modal consumes most of the screen but mostly displays:

- Selector controls.
- A summary box.
- A legend.
- Date buttons.

It does not provide enough chart value.

## 11.2 Create a dedicated page

Create a full-screen route:

```text
Sales Trend
```

Use a standard app bar with a back arrow.

Suggested structure:

```text
Sales Trend

[ Week ] [ Month ] [ Year ]

‹              30 May – 5 June              ›

          Actual line chart or bar chart

Revenue        2,100.00
Purchases      2,200.00
Net             -100.00
```

## 11.3 Chart requirements

The page must contain an actual visual chart.

Use:

- An existing chart dependency if the project already includes one.
- Otherwise, prefer a maintainable implementation using Flutter primitives or a small `CustomPainter`.
- Avoid adding a new dependency unless it is justified and compatible with the project.

Chart behavior:

- Display revenue and purchases over time.
- Use distinguishable series.
- Include a legend.
- Include readable axis labels.
- Use a selected-period summary.
- Support empty data.
- Support a single data point.
- Avoid unreadable labels on narrow devices.

## 11.4 Chart accessibility

Do not rely only on the plotted lines or bars.

Provide a semantic summary and an accessible textual representation.

Example:

```text
Sales trend from 30 May to 5 June.
Revenue: 2,100.00.
Purchases: 2,200.00.
Net: -100.00.
```

If feasible, retain a compact tabular summary beneath the chart.

---

# 12. Redesign Settings

## 12.1 Remove duplicate title

The current Settings page shows `Settings` twice.

Use only:

```text
← Settings
```

in the app bar.

Do not add a second oversized `Settings` heading inside the body.

## 12.2 Main settings page

The main Settings page should contain high-level sections only.

Suggested structure:

```text
Settings

Device Sync
Manage connected cashier devices                  >

Backup and Restore
Save or restore store data                         >
```

Use compact `ListTile`-style rows or reusable settings-section cards.

Do not show:

- A QR code.
- A raw local IP address.
- Pairing state.
- Backup action buttons.

directly on the main Settings page.

## 12.3 Device Sync page

Create a dedicated route:

```text
Device Sync
```

Default state:

```text
Main Device
This device stores the inventory database.

Connected Cashier Devices
2 devices connected

[ Connect Another Device ]
```

If connected-device details exist, list them below:

```text
Cashier Phone
Last seen: 4 minutes ago                           >
```

## 12.4 Pairing mode

Only reveal the QR code after the user explicitly taps:

```text
[ Connect Another Device ]
```

During active pairing:

```text
Scan this QR code from the cashier device.

[ QR code ]

[ Stop Pairing ]
```

Rename:

```text
Stop Connecting → Stop Pairing
```

The QR code must not dominate settings when pairing is inactive.

## 12.5 Technical details

Move the local IP address into an expandable section:

```text
Technical details                                  v
```

Expanded:

```text
Local address
http://10.x.x.x:40739
```

The address remains available for debugging but does not distract ordinary users.

## 12.6 Backup and Restore page

Create a dedicated route:

```text
Backup and Restore
```

Suggested structure:

```text
Last successful backup
Today, 18:41

[ Save Backup ]

[ Restore Backup ]
```

Use clear explanatory text:

```text
Save a backup file so your store data can be
recovered if this device is lost or replaced.
```

## 12.7 Backup error handling

Inspect the current Android backup implementation.

The current behavior may fail with an exception similar to:

```text
PathAccessException
Operation not permitted
```

Do not merely swallow this exception or show raw technical text.

Implement an appropriate storage strategy:

### Preferred behavior for a user-exported backup

Use a platform-compatible file picker or document-save flow so the user chooses where to save the backup.

On Android, prefer a Storage Access Framework-compatible flow such as a system document picker.

Expected UX:

1. User taps `Save Backup`.
2. The system file picker opens.
3. User selects the destination.
4. App writes the backup.
5. App shows:

```text
Backup saved successfully
```

If writing fails, show an actionable message:

```text
Could not save the backup.

Choose another folder or check that the selected
location is writable.
```

### Preferred behavior for internal automatic snapshots

If the app also keeps internal safety snapshots:

- Store them in app-specific storage.
- Do not confuse them with the user-exported backup.
- Explain that internal snapshots may disappear if the app is uninstalled.

### Avoid unnecessary broad permissions

Do not add broad storage permissions unless the application genuinely requires them and the existing implementation cannot use a safer alternative.

Do not request permissions preemptively on app launch.

Tie any permission request or system picker directly to the user’s backup action.

## 12.8 Restore flow

When the user taps:

```text
[ Restore Backup ]
```

Open a file picker or use the existing restore selection flow.

Before applying the restore, show a confirmation dialog:

```text
Restore backup?

Current store data may be replaced by the selected
backup file.

[ Cancel ] [ Restore ]
```

Requirements:

- Validate the backup before mutating current data.
- Preserve current data when validation fails.
- Show an actionable error for invalid files.
- Do not show stack traces.
- Confirm success clearly.
- Refresh app state after a successful restore.

---

# 13. Shared Inline Feedback Patterns

## 13.1 Success

Use a brief snackbar or inline banner:

```text
Sale completed
Inventory updated
Backup saved successfully
Backup restored successfully
```

## 13.2 Warning

Use inline banners when attention is needed:

```text
⚠ 3 transactions have not synced.
```

## 13.3 Error

Use specific, local, actionable text:

```text
Only 2 items are available in stock.
Reduce the quantity to continue.
```

```text
Could not save the backup.
Choose another folder or check that the selected
location is writable.
```

## 13.4 Loading

Use clear loading states for:

- Search if needed.
- Reports.
- Chart loading.
- Backup creation.
- Restore validation.
- Device pairing startup.

Prevent duplicate actions while an operation is running.

Example:

```text
Saving backup…
```

Disable the relevant button during the operation.

---

# 14. Centralize UI Strings

Do not scatter new visible strings throughout unrelated widgets.

If localization infrastructure already exists, add strings through that system.

If localization does not yet exist, create a lightweight central strings file or constants structure for the new copy.

Include at least:

```text
Sell
Restock
Inventory
Reports
Settings
Sale history
Restock history
Scan
Scan barcode
Scan barcode or search product
Search products or scan barcode
No products added yet
Complete Sale
Add to Inventory
Create New Product
Add Product
All
Low Stock
Revenue
Purchases
Gross Profit
Gross Margin
Low-stock Items
View Sales Trend
Device Sync
Connect Another Device
Stop Pairing
Technical details
Backup and Restore
Save Backup
Restore Backup
Backup saved successfully
Backup restored successfully
```

Keep terminology consistent.

Do not use both `item` and `product` randomly. Prefer `product` in user-facing copy.

---

# 15. Suggested Widget Organization

Adapt file names to the existing project structure. Do not create unnecessary fragmentation.

A reasonable organization might be:

```text
lib/
  app/
    app.dart
    app_theme.dart
    main_shell.dart

  shared/
    widgets/
      app_page_scaffold.dart
      inline_status_banner.dart
      product_lookup_bar.dart
      quantity_stepper.dart
      transaction_empty_state.dart

  features/
    sell/
      sell_screen.dart
      widgets/
        sale_item_tile.dart
        sale_summary.dart

    restock/
      restock_screen.dart
      widgets/
        restock_item_tile.dart
        restock_summary.dart

    inventory/
      inventory_screen.dart
      product_details_screen.dart
      widgets/
        inventory_product_tile.dart
        inventory_filters.dart

    reports/
      reports_screen.dart
      sales_trend_screen.dart
      widgets/
        report_metric_card.dart
        report_period_selector.dart
        sales_chart.dart

    settings/
      settings_screen.dart
      device_sync_screen.dart
      backup_restore_screen.dart
      widgets/
        settings_section_tile.dart
        pairing_panel.dart
```

Use the current project conventions if they differ.

Do not reorganize the entire repository merely to match this example.

---

# 16. Layout Details

## 16.1 Root screens

Recommended body structure:

```dart
SafeArea(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: ...
  ),
)
```

If `Scaffold.appBar` and `NavigationBar` already handle system insets, avoid redundant padding that creates excess whitespace.

## 16.2 Transaction screen

Use a column:

```dart
Column(
  children: [
    ProductLookupBar(...),
    const SizedBox(height: 16),
    Expanded(
      child: transactionItems.isEmpty
          ? const TransactionEmptyState(...)
          : ListView.separated(...),
    ),
    StickyTransactionSummary(...),
  ],
)
```

This allows:

- Search at top.
- Scrollable items in the middle.
- Primary completion action visible at bottom.

## 16.3 Inventory

Use:

```dart
Column(
  children: [
    ProductLookupBar(...),
    const SizedBox(height: 12),
    InventoryFilterRow(...),
    const SizedBox(height: 12),
    Expanded(
      child: ListView.builder(...),
    ),
  ],
)
```

## 16.4 Reports

Use a scrollable body because content may grow with text scaling:

```dart
SingleChildScrollView(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReportPeriodSelector(...),
      DateNavigator(...),
      CashierFilter(...),
      MetricGrid(...),
      SalesTrendButton(...),
      if (hasSyncIssue) InlineStatusBanner(...),
    ],
  ),
)
```

## 16.5 Settings

Use a simple list:

```dart
ListView(
  padding: const EdgeInsets.all(16),
  children: [
    SettingsSectionTile(...),
    const SizedBox(height: 12),
    SettingsSectionTile(...),
  ],
)
```

---

# 17. Avoid Common Flutter UI Mistakes

Do not:

- Nest multiple scrollable widgets without constraints.
- Put `ListView` inside a `Column` without `Expanded`.
- Hard-code screen heights.
- Assume one device width.
- Use `GestureDetector` for standard button behavior when `IconButton`, `ListTile`, `FilledButton`, or `OutlinedButton` is appropriate.
- Use icon-only buttons without tooltips.
- Use color as the only error indicator.
- Display raw exceptions.
- Rebuild the full inventory list unnecessarily for every unrelated state change.
- Add a chart dependency without checking whether one already exists.
- Change database or sync behavior as a side effect of visual cleanup.
- Replace tested business logic with duplicate UI-side calculations.

---

# 18. Automated Tests

Add or update tests. Use existing repository conventions.

Run:

```bash
dart format .
flutter analyze
flutter test
```

Fix failures introduced by this task.

## 18.1 Widget tests: Sell

Add tests for:

1. Sell screen displays guided empty state.
2. Complete Sale button is disabled when no products exist.
3. Typing a product name displays matching suggestions.
4. Selecting a suggestion adds the product.
5. Added product defaults to quantity `1`.
6. Increment increases quantity.
7. Decrement decreases quantity safely.
8. Remove deletes the row.
9. Insufficient stock highlights only the offending row.
10. Insufficient-stock warning includes visible explanatory text.
11. Completion remains disabled when existing policy prohibits negative inventory.
12. Successful completion clears the cart.
13. Failure preserves the cart.

## 18.2 Widget tests: Restock

Add tests for:

1. Restock screen displays guided empty state.
2. Existing product selection shows current stock.
3. Quantity defaults to `1`.
4. Primary action reads `Add to Inventory`.
5. Unknown barcode offers `Create New Product`.
6. Scanned barcode is prefilled in new-product flow.
7. Required-field errors appear inline.
8. Successful restock clears the form.

## 18.3 Widget tests: Inventory

Add tests for:

1. Inventory shows compact tappable product rows.
2. Product row opens details.
3. Search filters product rows in near real time.
4. Low-stock filter displays only matching products.
5. Add Product is visibly labeled.
6. Empty inventory state contains an Add Product action.
7. Empty search state shows the query.

## 18.4 Widget tests: Reports

Add tests for:

1. Reports screen contains only one title.
2. Period selector works.
3. Date navigation updates the visible period.
4. Metrics use correct labels.
5. Gross Profit versus Gross Margin label matches the actual value semantics.
6. Healthy sync state does not show technical diagnostics.
7. Unsynced state shows a warning banner.
8. View Sales Trend opens a dedicated route.
9. Trend page renders an actual chart widget.
10. Trend page provides a textual summary.

## 18.5 Widget tests: Settings

Add tests for:

1. Settings screen contains only one title.
2. Main settings screen does not expose QR code by default.
3. Main settings screen does not expose raw IP address by default.
4. Device Sync opens a dedicated page.
5. Connect Another Device reveals pairing UI.
6. Active pairing shows the QR code.
7. Button label reads `Stop Pairing`.
8. Technical details are collapsed by default.
9. Expanding technical details shows local address.
10. Backup and Restore opens a dedicated page.
11. Restore requires confirmation.
12. Invalid backup does not mutate current data.
13. Backup errors show actionable user-facing messages.

## 18.6 Accessibility tests

Enable semantics and add checks where feasible:

```dart
final handle = tester.ensureSemantics();

await expectLater(
  tester,
  meetsGuideline(androidTapTargetGuideline),
);

await expectLater(
  tester,
  meetsGuideline(labeledTapTargetGuideline),
);

handle.dispose();
```

Use `textContrastGuideline` where compatible with the app theme and test environment.

Test at least:

- Sell screen.
- Restock screen.
- Inventory screen.
- Reports screen.
- Settings screen.
- Device Sync pairing state.
- Backup and Restore screen.

## 18.7 Keys

Add stable keys where needed for tests.

Examples:

```dart
const Key('sell-search-field')
const Key('sell-scan-button')
const Key('sell-complete-button')
const Key('restock-submit-button')
const Key('inventory-search-field')
const Key('inventory-low-stock-filter')
const Key('reports-view-trend-button')
const Key('settings-device-sync-tile')
const Key('settings-backup-restore-tile')
const Key('device-sync-start-pairing-button')
const Key('device-sync-stop-pairing-button')
```

Do not overuse keys when text or widget type is sufficient.

---

# 19. Manual QA Checklist

Run the app on an Android emulator or device and verify the following.

## 19.1 General

- No duplicate titles.
- No excessive unused header space.
- Bottom navigation works correctly.
- Tab state is preserved appropriately.
- Back navigation works from child pages.
- Settings is reachable from each root screen.
- No overflow warnings.
- No clipped buttons.
- Text remains readable at increased font scale.

## 19.2 Sell

- User can immediately tell how to begin.
- Scan button is obvious.
- Typing searches products.
- Selecting a product is fast.
- Quantity controls are easy to tap.
- Total remains visible.
- Complete Sale remains visible.
- Negative-stock row is clearly identified.
- Cart is preserved on recoverable failure.

## 19.3 Restock

- User understands that this flow adds inventory.
- Existing and unknown products behave clearly.
- Product creation is contextual.
- Quantity defaults correctly.
- Confirmation action is explicit.

## 19.4 Inventory

- More products fit on the screen than before.
- Rows remain comfortable to tap.
- Search works while typing.
- Low-stock filter works.
- Add Product is obvious.
- Product detail navigation is clear.

## 19.5 Reports

- Period controls fit or scroll intentionally.
- Date range is readable.
- Metrics use accurate terminology.
- Technical sync success details are absent.
- Warning appears only when synchronization needs attention.
- Trend page displays an actual chart.

## 19.6 Settings

- Main settings page is short and understandable.
- QR code is hidden until pairing begins.
- Raw IP address is hidden under technical details.
- Stop Pairing label is clear.
- Backup save flow opens an appropriate destination chooser.
- Backup failure gives an actionable message.
- Restore asks for confirmation.
- Invalid restore files do not destroy current data.

## 19.7 Device sizes

Test at least:

```text
320 × 568
360 × 800
412 × 915
```

Also test font scaling around:

```text
1.0
1.3
1.5
```

---

# 20. Completion Criteria

The task is complete only when:

1. Root screens use one compact app bar.
2. `Dekon` no longer consumes a large heading area on each root page.
3. `Buy` is presented to users as `Restock`.
4. Sell and Restock use one clear lookup field plus a scan action.
5. The ambiguous persistent plus icon is removed from lookup rows.
6. Search filters or suggests products while typing.
7. Unknown products offer a contextual Create New Product action.
8. Quantity is adjusted after adding a product.
9. Sale rows display local insufficient-stock warnings.
10. Sell and Restock confirmation actions remain visible near the bottom.
11. Inventory uses a compact searchable list.
12. Inventory includes All and Low Stock filters.
13. Inventory has a labeled Add Product action.
14. Reports use readable dates and accurate metric labels.
15. Reports hide healthy synchronization diagnostics.
16. Reports show a sync warning only when operator attention is required.
17. Sales Trend is a dedicated page with an actual chart.
18. Settings has no duplicate title.
19. Device Sync and Backup and Restore are dedicated settings pages.
20. Pairing QR code and local IP address are hidden by default.
21. Backup save failures result in actionable messages.
22. Restore requires confirmation and validation.
23. Interactive controls meet the minimum tap-target requirement.
24. Icon-only actions have tooltips and semantic labels.
25. `dart format .`, `flutter analyze`, and `flutter test` pass.

---

# 21. Final Report Format

After implementation, provide a concise report with:

## Summary

Explain the major UX and implementation changes.

## Changed Files

List the modified files and the purpose of each change.

## Preserved Behavior

State which domain behaviors were intentionally preserved:

- Database.
- Inventory rules.
- Sync protocol.
- Backup format.
- Offline behavior.

## Tests Added or Updated

List automated tests.

## Commands Run

Include:

```bash
dart format .
flutter analyze
flutter test
```

Report results accurately.

## Remaining Assumptions or Risks

Call out any unresolved issues, such as:

- Existing metric formula ambiguity.
- Missing chart data.
- Platform-specific backup plugin constraints.
- Missing connected-device metadata.
- Existing scanner limitations.

Do not claim a behavior was verified unless it was actually tested.
