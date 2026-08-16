# AGENTS.md — Order Fulfillment & Billing Manager

This file is the single source of truth for any coding agent working on
this project. Read this in full before making changes. It reflects the
CURRENT intended state of the app, including all fixes and feature changes
made since the original build — not the original build prompt alone.

---

## 1. What this app is

A Flutter Android app for a custom job-work / metal-fabrication business
("Success Engineering Enterprises" style business) that covers the full
Order-to-Cash cycle: **Customer → Product → Purchase Order → Delivery
Note → Invoice → Reports**. It replaces an existing Windows desktop app
(Access database + Crystal Reports) the business currently uses.

The business takes purchase orders from clients — some for selling
physical products outright ("Sales"), some for processing/job-work on
material the client already owns, like plating, press work, or CNC turning
("Labour") — delivers against those orders (often in multiple partial
deliveries), and invoices for what's been delivered (often partially,
across multiple invoices, sometimes consolidating multiple deliveries).

---

## 2. Tech Stack

- **Flutter** (latest stable), Android first
- **Storage backend: Microsoft OneDrive** — this is now the ACTIVE backend
  (`activeStorageBackend` in `lib/app.dart`).
  - Authentication: Microsoft identity platform v2.0, authorization-code flow
    with PKCE, public client. Implemented directly in
    `core/services/microsoft_auth.dart` rather than through an MSAL wrapper —
    session persistence is this app's most defect-prone area (§9), and a plugin
    buries exactly the behaviour that keeps regressing. Scopes are
    `Files.ReadWrite.AppFolder` **and** `offline_access` (the latter is what
    yields a refresh token; without it there is no silent restore at all).
    Never request `Files.ReadWrite.All`.
  - The refresh token is the only thing that survives a force-close. It lives
    in the platform keystore behind `SecretStore`, which is an interface so cold
    starts can be replayed in tests.
  - Data store: a single Excel workbook, `ERP_App_Data.xlsx`, in the app's
    OneDrive **app folder** (`/me/drive/special/approot`), one worksheet per
    entity, each a real Excel Table so Graph's table/row endpoints are used
    rather than raw cell ranges.
  - Microsoft Graph accessed via `http` REST calls
    (`core/services/onedrive_excel_service.dart`).
  - **Setup required before the app can sign in:** an Azure app registration
    (public client) whose client id is passed at build time as
    `--dart-define=MS_CLIENT_ID=...`, with a redirect URI matching
    `MicrosoftAuth.redirectUri`. See README.
  - **The old Google Sheets backend has been deleted**, along with the
    `google_sign_in` / `googleapis` dependencies and the one-off Sheets→OneDrive
    data import. Do not reintroduce them. If old data still needs importing, the
    import lived in Settings and is recoverable from git history — it was a
    `WorkbookTransfer.copy(from: SheetsService(), to: <store>)` over the same
    `WorkbookStore` interface, so re-adding it does not require touching
    anything else.

- **riverpod** — state management
- **pdf** + **printing** packages — generate/preview/print Delivery Notes
  and Invoices
- **uuid** — internal unique IDs (separate from human-readable sequential
  codes/numbers — see Section 4)
- **intl** — date and currency formatting
- **go_router** — navigation

---

## 3. Architecture Requirements

### Repository layer (mandatory abstraction)
One repository class per entity (`CustomerRepository`, `ProductRepository`,
`PurchaseOrderRepository`, etc.), each exposing:
- `Future<List<T>> loadAll()`
- `Future<void> save(T record)` (insert or update)
- `Future<void> delete(String id)`

All repositories go through a single shared storage service behind the
`WorkbookStore` interface — `OneDriveExcelService` — responsible for:
- Locating/creating the workbook and its tables on first run
- Caching the workbook's file ID and each table's headers after first lookup
- Mapping a table's rows to `Map<String, String>` and back using the header row
  as keys
- Maintaining an in-memory ID→row-number index per table, rebuilt on
  `loadAll()` (that index lives in `BaseRepository`, not the service)

`WorkbookStore` carries two contracts every backend must honour, documented on
the interface:
1. **Row addressing** is the 1-based spreadsheet row, header at row 1, first
   data row at 2. Graph table rows are 0-based and exclude the header, so
   `OneDriveExcelService` converts at its boundary — that conversion is the
   single riskiest line in the migration and is mutation-tested.
2. **`clearRow` blanks a row in place, never removes it.** Graph's
   `DELETE .../rows/itemAt(index=n)` shifts every later row up by one, which
   would silently invalidate the id→row index a bulk delete captured up front.
   The OneDrive backend therefore PATCHes blanks and must never call that
   DELETE.

**No UI code or business logic calls the storage API directly** — everything
goes through repositories, so storage can be swapped again later without
touching UI code.

The startup/auth flow depends on a narrow `StorageBackend` interface
(`restoreSession()` / `signIn()` / `signOut()` / `isReady`) rather than on the
concrete service, so routing is backend-agnostic and can be tested with a fake.

### Per-row optimistic locking (two-device conflict handling)
Every mutable row (Customers, Products, PurchaseOrders,
PurchaseOrderItems) carries an `updated_at` column. Before writing:
1. Track the row's `updated_at` at load time.
2. Before saving, re-read just that row's `updated_at`.
3. If unchanged, proceed and set a fresh `updated_at`.
4. If changed, do NOT overwrite — show: "This record was updated from
   another device. Reloading the latest version — please redo your last
   action." Reload just that record and return the user to their previous
   screen state.

This lives in the shared repository base class, not copy-pasted per
repository. Whether an entity participates is derived from whether its table
declares an `updated_at` column, so it cannot drift out of sync with the
schema — a hand-maintained column index previously pointed at the wrong
column and stamped timestamps into `cst_number`.

Rows are mapped to/from `Map<String, String>` using the worksheet's OWN header
row as keys, never fixed positions. Adding a column therefore never shifts
existing data, and a workbook written by an older build still reads (unknown
columns are appended to the header on first run; missing values read as empty).

---

## 4. Data Model

One workbook, one table per entity. Human-readable sequential codes
(Customer Code, Product Code, PO Number, Delivery Note Number, Invoice
Number) are separate from the internal relational ID used for joins
between tables — never replace or repurpose the internal ID when adding a
display code.

### Customers
`customer_id, customer_code, name, phone, email, street, area, city_district, state, country, pincode, gst_number, tin_number, cst_number, created_at, updated_at`
- Address is stored as separate fields (Street, Area/Locality,
  City/District, State, Country [default "India"], Pincode) — never a
  single free-text address blob.
- GST Number, TIN Number, CST Number are three separate optional fields —
  never combined into one.
- Duplicate check on create: block if BOTH name AND phone (case-
  insensitive, trimmed) match an existing customer.
- Phone, if filled in, must be exactly 10 digits. Email, if filled in,
  must match standard email format. Both show live inline error text, not
  just a disabled button.

### Products
`product_id, product_code, name, part_no, category, unit, price, tax_percent, hsn_sac, created_at, updated_at`
- `category` is a required dropdown: "Sales" or "Labour."
  - Sales = physical product sold outright, uses an HSN code.
  - Labour = job-work/processing on customer-owned material, often priced
    at ₹0, uses a SAC code.
- `part_no` (renamed from "SKU") is optional free text, alphanumeric, NOT
  required to be unique, can be blank.
- `unit` is a dropdown: Nos, Kgs, Pcs, Box, Litre, Metre, Other (with
  free-text fallback if Other is chosen).
- `hsn_sac` (renamed from "HSN Code") is free text, no numeric-only
  restriction — holds either an HSN or SAC code depending on category.
- Duplicate check: unique on `product_code` (the generated code), NOT on
  `part_no`.
- Editing a product's price/tax_percent must NEVER retroactively change
  the rate/tax already recorded on existing PurchaseOrderItems rows — PO
  line items snapshot the rate at the time of order.
- **Deferred, not yet implemented:** scoping Products to a specific
  customer (real-world data shows each product belongs to one client).
  Currently Products remain a single shared list app-wide. Do not change
  this without explicit instruction — see Section 8.

### PurchaseOrders
`po_id, po_number, customer_id, order_date, client_po_number, client_po_date, client_delivery_note_number, client_delivery_note_date, status, created_at, updated_at`
- `status`: one of `Pending`, `Partially Delivered`, `Delivered`,
  `Invoiced` — this four-stage model is the deliberate, final choice; do
  not simplify it to match the real business's simpler "In"/"Invoiced"
  status vocabulary (a real difference was found, but the four-stage
  model was chosen to keep).
- `client_delivery_note_number` / `client_delivery_note_date`: the
  CLIENT's own delivery challan reference for material they sent to this
  business for processing, captured at PO creation time — distinct from
  this business's own DeliveryNotes (used later to ship finished goods
  back). Optional fields, can be blank/N/A.
- PO Number format: `PO/{S|L}{FY}/{sequence}` — e.g. `PO/S2026-27/4` for a
  Sales-category order, `PO/L2026-27/73` for Labour. `{FY}` is derived
  from `order_date` using the Indian financial year convention (April to
  March: a date of Jan–Mar 2027 is still FY "2026-27"). The counter
  sequence is keyed on (entity + category + financial year) as a compound
  key, not just entity name — each combination has its own independent
  sequence. If a PO's line items mix Sales and Labour products, confirm
  with the business how the prefix should be determined before assuming a
  rule. **Until that is confirmed, the app asks the user** at save time
  ("This order contains both Sales and Labour items — which sequence should
  the PO number use?") rather than guessing. Replace that prompt with the
  real rule once the business states it.
- **Deferred, not yet implemented:** a "Scrap: Yes/No" flag seen in the
  real business data — do not add until its business purpose is
  clarified with the business. See Section 8.

### PurchaseOrderItems
`po_item_id, po_id, product_id, quantity, rate, delivered_qty, pending_qty, remarks, updated_at`
- `rate` is captured at PO creation, pre-filled from the product's current
  price but fully editable (allows negotiated/one-off pricing), and never
  live-linked back to the product master afterward.
- `remarks`: optional free text per line item, independent of other line
  items on the same PO (only the items that need a remark should have
  one).

### DeliveryNotes
`dn_id, dn_number, po_id, delivery_date, created_at`

### DeliveryNoteItems
`dn_item_id, dn_id, po_item_id, delivered_qty, remarks`
- `delivered_qty` on this row is the quantity delivered IN THIS SPECIFIC
  NOTE, never a cumulative or overwritten total.
- `remarks`: optional free text per line item (e.g. "Sent for vacuum
  hardening 58-62 RC"), independent per item.

### Invoices
`invoice_id, invoice_number, po_id, invoice_date, subtotal_amount, cgst_percent, cgst_amount, sgst_percent, sgst_amount, total_amount, amount_in_words, transport_mode, vehicle_number, status, created_at`
- CGST % and SGST % default to 9% each on the invoice generation screen,
  but are fully editable per invoice — store the ACTUAL rate used on this
  row so a reprinted invoice always shows the rate that applied at the
  time, even if the default changes later.
- `status`: `Pending` or `Paid` — must be changeable via an explicit "Mark
  as Paid" action on the invoice detail screen (with a confirmation
  dialog); there is no automatic transition.
- `amount_in_words`: total amount converted to words using Indian
  numbering convention (lakhs/crores).
  - This originally said "use a well-tested package, not hand-rolled
    logic". No usable package exists: `indian_currency_to_word` 1.0.0 is the
    only published option and emits malformed output ("One   Rupees",
    "Twenty Thousands") and the literal string "Number is too large" above
    ₹99,99,99,999 — unacceptable on a GST document. It was evaluated and
    rejected. `lib/core/services/number_to_words.dart` is used instead and is
    covered by unit tests (`test/number_to_words_test.dart`) including paise
    rounding, float noise, and crore-scale amounts. Revisit if a maintained
    package appears.
- **Open/unconfirmed:** whether one invoice should be able to consolidate
  multiple delivery notes (possibly across different POs) into a single
  document — the real business's sample invoice showed this. Do not
  implement multi-delivery-note consolidation without explicit
  confirmation; the current model is one PO's delivered-but-uninvoiced
  quantity per invoice, with partial invoicing supported across multiple
  invoices for the same PO.

### InvoiceItems
`invoice_item_id, invoice_id, po_item_id, product_id, description, hsn_sac, quantity, rate, amount, remarks`
- `po_item_id` links the billed quantity back to the specific PO line item.
  It is required, not optional: the invoiceable-quantity rule below is defined
  per `po_item_id`, and without it the derivation has to fall back to
  `product_id`, which silently merges two PO lines that happen to use the same
  product. Blank on flat-charge rows.
- Support TWO kinds of line item:
  1. Normal: product + quantity + rate, amount computed as quantity ×
     rate.
  2. Flat charge: a named charge (e.g. "Weighment Charges") with just a
     description and an amount — no product/quantity/rate/HSN required.
- `amount` is EXCLUSIVE of tax for both kinds, so the Amount column on the
  printed invoice always sums exactly to `subtotal_amount`. CGST/SGST are
  applied once, at invoice level — never baked into line amounts.
- Zero-rate items (rate = 0): excluded from — or clearly marked
  "No invoice needed" and unselected by default on — the invoiceable-
  quantity list when generating an invoice. A PO can be considered fully
  invoiced even if its only remaining un-invoiced items are zero-rate.
- "Invoiceable quantity" for an item is a DERIVED value at screen-load
  time: `delivered_qty − sum(already invoiced quantities for that
  po_item_id across all InvoiceItems)`. Never stored as a column. This is
  a different number from the PO's `pending_qty` — do not conflate them.
- Invoice-line remarks are optional; only add a Remarks column to the
  printed invoice if at least one line item on that invoice actually has
  one.

### Counters
`entity_name, category, financial_year, last_number` (compound key on
entity_name + category + financial_year, since PO numbering needs
independent sequences per category/year combination — other entities that
don't need category/year splitting can leave those fields blank/constant)
- Formats for the entities with no category/FY split, which this document
  did not previously specify: `CUST-0001`, `PRD-0001`, `DN-0001`, `INV-0001`
  (zero-padded to four digits, one continuous sequence each). Only the PO
  number has a prescribed scheme.

### Company Profile (singular, not a table with multiple rows)
`company_name, street, area, city_district, state, country, pincode, gst_number, tin_number, cst_number, phone, email, website, logo_asset_path`
- Set once via Settings/onboarding, used as the letterhead on every
  printed Delivery Note and Invoice.
- If not yet filled in, PDFs show a friendly placeholder rather than a
  blank gap.

---

## 5. Core Business Logic

**Creating a PO:** writes one PurchaseOrders row + N PurchaseOrderItems
rows, `pending_qty = quantity`, `delivered_qty = 0` initially, status
`Pending`. PO Number generated per the category+FY scheme in Section 4.

**Recording a delivery:** user selects a PO, sees items with
`pending_qty > 0`, enters delivered quantities (validated ≤ pending_qty,
> 0, inline error). A blank quantity means "not shipping this line in this
note" — deliveries are routinely partial across ITEMS as well as across
quantities, so items must not all be mandatory; at least one line must have
a quantity. On save: new DeliveryNotes + DeliveryNoteItems rows
(delivered_qty on each item row = quantity delivered IN THIS transaction
only); update PurchaseOrderItems (`delivered_qty +=`, `pending_qty -=`,
refresh `updated_at`); recalculate PO status (`Delivered` if every item's
pending_qty == 0, else `Partially Delivered` if any item has
delivered_qty > 0, else stays `Pending`). PDF only generated after the
write succeeds.

**Generating an invoice:** user selects a PO with invoiceable quantity
(see InvoiceItems above for the derivation), enters quantities to bill
(partial invoicing allowed, validated against invoiceable qty not pending
qty), computes line amounts and CGST/SGST (defaulting 9%/9%, editable),
writes Invoices + InvoiceItems, updates PO status to `Invoiced` only if
every item is now fully invoiced.

**ID/number generation:** read Counters row for the
(entity+category+FY) key, increment, format, write back — tied to the
same logical save as the record it numbers, so a failed record save never
burns a number.

**Reports:** computed entirely in-memory from already-loaded repository
data (no fresh Graph API calls at report time) — pending deliveries, sales
by customer, sales by product, outstanding invoices (dependent on
Invoice.status actually being maintained via Mark-as-Paid). Each report
screen has a From/To date-range filter, defaulting to the current month.

**Customer outstanding balance:** shown as a two-number summary (total
invoiced, total outstanding/unpaid) on the Customer detail screen,
computed from that customer's Invoices where status ≠ Paid.

---

## 6. PDF / Print Requirements

- Every Delivery Note and Invoice PDF prints the Company Profile as a
  letterhead (logo top-left, company name/address/GST-TIN-CST) matching
  the reference sample layout the business provided.
- Every Delivery Note and Invoice generates **three labeled copies**:
  "Original - For Recipient," "Duplicate - For Transporter," "Triplicate -
  For Supplier" — standard Indian GST document convention. All three are
  always produced; it is not an option the user has to select.
- **Each copy is its own separate PDF file**, not three pages of one
  document. (This replaces the earlier "three pages in the same PDF" rule,
  changed on request: the copies go to different parties, so they have to be
  sendable and printable individually.) After saving a Delivery Note or an
  Invoice — and from the Invoice detail screen at any time — a sheet offers
  "Save all 3 PDFs" plus per-copy save and print. Files are named
  `{document number} - {copy} ({audience}).pdf`, e.g.
  `INV-0042 - Duplicate (For Transporter).pdf`; characters illegal in a file
  name are replaced.
- **PDF text must stay within Latin-1.** The base-14 PDF fonts have no Unicode
  support, and an unsupported character is not flagged — it renders as
  *nothing*. An en dash in the copy label silently printed "Original  For
  Recipient" on every document until this was caught. Use `-` not `–`/`—`,
  and `|` not `•`, in anything that reaches a PDF.
  `test/pdf_copies_test.dart` asserts the copy labels are Latin-1 encodable;
  extend that guard when adding fixed strings. (Customer-entered text outside
  Latin-1 remains a known limitation — it would need an embedded Unicode
  font.)
- Delivery Note item table: Item # | Product Details | Qty (with unit) |
  Remarks (per item).
- Invoice item table: Item # | Product Description | HSN/SAC | Qty | Rate
  | Amount — supports both normal (qty×rate) and flat-charge (amount only)
  line items in the same table.
- Invoice tax section shows CGST % + amount, and SGST % + amount,
  separately — never combined into a single "Tax" line.
- Invoice shows the amount-in-words line, Transportation Mode, and Vehicle
  Number, matching the reference sample.
- Customer/company GST, TIN, CST fields print with "None/Blank" as
  literal text when empty, not a blank gap.
- Address fields print joined sensibly: Street, then Area, then
  "City/District, State, Country - Pincode."

---

## 7. UI/UX Requirements

- Material 3 (`useMaterial3: true`), one deep teal/navy primary + one warm
  accent color, defined centrally in a ThemeData/ColorScheme file — no
  inline colors.
- 8/16/24px spacing scale, 12–16px corner radius, subtle elevation instead
  of borders. Generous whitespace over dense layouts.
- Company logo used on: Sign-In screen, splash/loading screen, Drawer
  header, both PDF letterheads, and the Android app icon.
- Hero transitions on list-item → detail-page navigation. Implicit
  animations (AnimatedContainer/AnimatedSwitcher) only on status badge
  changes and list item add/remove — not elsewhere.
- Skeleton/shimmer loading placeholders, never a bare spinner on a blank
  screen.
- Every list screen has a proper empty state (icon + short message + CTA
  button) and a consistently-placed floating "add new" button and visible
  search bar.
- Forms: inline validation with live visible error text under the
  relevant field (never just a silently-disabled submit button), submit
  disabled until valid, loading state on submit (prevents double-submit).
- Faster multi-line item entry on PO/Delivery/Invoice: after adding a
  line item, the entry form stays open and focused on the next Product
  field, with added items shown in a compact running list above the form;
  editing/removing an already-added item is possible without restarting
  entry; an explicit "Done/Review" step shows the full summary before
  final save.
- Status pill widget, shared and reused everywhere: Pending = amber,
  Partially Delivered = blue, Delivered = green, Invoiced = purple.
- Drawer navigation for the 6 sections: Dashboard, Customers, Products,
  Purchase Orders, Invoices, Reports.
- Dashboard content is fully scrollable (no cut-off cards/quick actions),
  with safe-area padding at the bottom.
- Every non-root screen has both a visible AppBar back arrow AND correctly
  responds to the hardware/gesture back button (pops back one screen, not
  out of the app) — this must hold true on every single screen, audited
  app-wide, not screen-by-screen as bugs are reported.
  - The six drawer destinations are root screens: they show the drawer
    hamburger rather than a back arrow. Tapping a drawer destination resets
    to Dashboard and then pushes the destination, so the stack is always
    exactly two deep: back from a section returns to Dashboard, back from
    Dashboard leaves the app. Pushing each destination without the reset
    piles up an unbounded stack that the hardware back button then has to
    unwind one screen at a time.
- Light + dark mode via `ThemeMode.system`.

---

## 8. Explicitly deferred — do not implement without new instruction

1. **Per-customer product scoping.** Real business data shows every
   product belongs to one specific customer, not a shared catalog. This
   would require Product Master to work within a selected customer's
   context, and PO's product picker to be scoped to the PO's customer.
   Confirmed as a real difference but intentionally not yet built.
2. **"Scrap: Yes/No" flag on Purchase Orders.** Present in real business
   data, business purpose not yet clarified. Do not add.
3. **Multi-delivery-note invoice consolidation.** See Invoices section
   above — needs explicit confirmation before changing the invoice
   creation flow's underlying structure.

---

## 9. Known-sensitive / recurring issue — verify thoroughly, don't assume fixed

**Sign-in session persistence.** This has been reported fixed multiple
times across development and has recurred each time — the app has shown
the Sign-In screen on reopen instead of restoring a valid session and
landing on Dashboard. Any change touching auth/routing/startup MUST be
verified by force-closing and reopening the app at least 5 times in a row
with zero visible flash of the Sign-In screen, and by adding temporary
diagnostic logging around `signInSilently()`-equivalent calls and the
router's initial routing decision if the issue reappears — to identify
whether it's a routing race condition, a genuinely failing/expiring
session, or the router rendering a default screen before auth state
resolves. Do not mark this fixed without that verification.

### Root cause found (do not re-guess this)

It was never a routing race. `trySilentReAuth()` restored the Google account
and rebuilt the HTTP client but **never located the workbook**, so
`_spreadsheetId` stayed null. Startup then ran a round-trip test that wrote to
the sheet, which threw a null-check error, which the startup catch-all
swallowed and turned into `stage = signIn`. Silent sign-in therefore fell
through to the Sign-In screen *every single time*, on every launch, no matter
what the router did — which is exactly why fixes aimed at routing never held.
A second path made it worse: `stage = error` (e.g. a momentary network
failure) also redirected to `/sign-in`, so a blip looked like a sign-out.

### Invariants that now hold — preserve these

1. `restoreSession()` restores the session **and** prepares the data store, or
   it reports failure. It never reports success on a half-initialised store.
2. `StorageBackend.isReady` is asserted after a successful restore. "Signed in
   but store not ready" is an error state, not a Dashboard.
3. The app's initial route is the splash. Dashboard and Sign-In are only
   reachable once the stage justifies them.
4. Bootstrap starts at provider creation, not from a widget's `initState`, so
   no frame can render before the stage is `checking`.
5. A `session_established` flag is persisted the first time a session works.
   **While it is set, a failed restore routes to a retry screen, never to
   Sign-In.** Only an explicit sign-out clears it. Signing out is therefore the
   only path back to the Sign-In screen.
6. Startup and the router's redirect decisions log under `[Startup]` in debug
   builds. This logging is permanent, not temporary — the next investigation
   should start from evidence.

`test/session_persistence_test.dart` replays five consecutive cold starts
asserting the Sign-In screen is absent on every frame, and covers each failure
mode that must not show Sign-In. Both the routing fix and the
`session_established` fix were mutation-tested: reverting either makes that
suite fail. Run it before touching anything in this area.

---

## 10. Error Handling & Edge Cases (baseline, applies throughout)

- No internet → clear message, retry button, no crash.
- Auth token expiry → silent re-auth attempt, fall back to sign-in only if
  that genuinely fails.
- Empty/corrupted table data → treated as empty dataset, warning logged,
  no crash.
- Delivering more than pending quantity → blocked, inline error.
- Invoicing more than invoiceable quantity → blocked, inline error (must
  check invoiceable quantity, not pending quantity).
- Deleting a customer/product referenced by an existing PO → blocked with
  a clear warning (referential integrity).
- **Deletion, single and bulk.** Customers, Products, Purchase Orders and
  Invoices can each be deleted one at a time (from the detail/edit screen) or
  several at a time from their list screen. Long-press a row to enter selection mode, tap
  rows to toggle, "select all" and "delete" sit in the contextual app bar, and
  the hardware back button cancels the selection rather than leaving the
  screen.
  - **Bulk delete is partial, never all-or-nothing.** Records that are safe to
    remove are removed; records that are still referenced are KEPT and reported
    back ("3 deleted • 2 kept — it is linked to 1 purchase order(s)"). One
    protected record must not block the rest of the batch.
  - **Deleting a Purchase Order cascades** to its PurchaseOrderItems, its
    DeliveryNotes and their DeliveryNoteItems. The confirmation dialog states
    those counts before anything is touched.
  - **A Purchase Order with any Invoice against it cannot be deleted.**
    Invoices are financial records; removing the order beneath them would
    orphan the documents and silently change the Sales-by-Customer,
    Sales-by-Product and Outstanding-Invoices reports. Delete the invoices
    first — the PO detail screen lists them, so that block is actionable.
    Delivery notes do NOT block, because they exist only to describe that
    order's shipments.
  - **Deleting an Invoice** removes its InvoiceItems and then re-derives the
    purchase order's status, because the quantity it billed becomes invoiceable
    again: `Invoiced` must not survive the deletion of the invoice that
    justified it. Nothing references an invoice, so nothing blocks — including
    a `Paid` invoice, which is deletable but flagged as PAID in the
    confirmation dialog. Making Paid invoices undeletable would recreate the
    dead end where an invoiced PO could never be removed.
  - Nothing may be permanently undeletable. Every block must name the records
    the user has to remove first, and those must themselves be deletable.
    Deleting an invoice is what unblocks its purchase order; that whole chain
    is covered end to end in `test/delete_test.dart`.
  - "Can nothing in this selection be deleted?" is counted in RECORDS, not in
    cascade rows. Deriving it from cascade counts wrongly reported a whole
    batch as blocked whenever the only deletable order had no line items.
  - Confirmation dialogs must name the cascade explicitly. Never delete
    dependent records the user wasn't told about.
  - Covered by `test/delete_test.dart` against an in-memory workbook.
- Deleting blanks a row in place rather than removing it, so surviving rows
  keep their sheet indices and the id→row map stays valid mid-batch. Any
  replacement backend must preserve that property or `BaseRepository`'s index
  arithmetic has to change with it.
- Graph API rate limit → one retry with backoff, then a clear "try again
  in a moment" message, not a crash.

---

## 11. Testing expectations for any change

Whenever a change touches calculation logic (invoice totals, tax,
delivered/pending quantities), verify with a hand-calculated example
before considering it done — several past rounds of testing found the
calculation logic itself was correct, so don't re-derive it from scratch,
but any NEW logic added must be verified the same way.

The calculation rules now live in pure, Flutter-free helpers
(`core/services/invoice_math.dart`, `number_to_words.dart`,
`address_format.dart`, `counter_helper.dart`) precisely so the hand-calculated
examples can be written down as tests instead of re-derived each round. Add the
worked example to the matching test file rather than only checking it by eye.

---

## 12. OneDrive migration — status

**Code complete and covered by tests; NOT yet verified against a real
Microsoft account or a physical device.** Treat the two as different things.

### What was built

- `WorkbookStore` / `WorkbookSchema` (`core/services/workbook_store.dart`) —
  the backend-neutral row interface and the single schema declaration. Both
  backends implement it; repositories know nothing else.
- `MicrosoftAuth` — PKCE authorization-code flow, refresh-token persistence
  behind `SecretStore`, silent restore, and a clear split between "no session"
  (`NoStoredSessionException` → Sign-In) and "session exists but something
  failed" (`StorageUnavailableException` → retry screen).
- `OneDriveExcelService` — app-folder workbook discovery/creation, worksheet
  and Excel Table creation, non-destructive header reconciliation, header-keyed
  row I/O, blank-in-place delete, and Graph throttling handled by honouring
  `Retry-After`.
- `BlankWorkbook` — builds a minimal valid `.xlsx` in memory. Graph rejects a
  zero-byte file, so a real Office Open XML package has to be uploaded before
  any worksheet/table call will work.
- `WorkbookTransfer` + a Settings action — one-off copy of the old Google
  Sheets data into OneDrive, idempotent (a destination table that already holds
  data is skipped, so a second run cannot duplicate the dataset).
  **Since removed** along with the Sheets backend; see below.

### Verified by tests

- `test/onedrive_store_test.dart` — workbook/table setup, app-folder-only
  access, header reconciliation on an older workbook, row addressing, and that
  the row-DELETE endpoint is never called.
- `test/onedrive_session_test.dart` — §9 re-proved on the new auth stack,
  including **five consecutive cold starts** restoring silently, offline and
  locked-keystore both routing to retry rather than Sign-In, and a revoked
  refresh token being a real sign-out.
- `test/onedrive_repository_test.dart` — the repository layer and business
  logic over the real service: optimistic locking, conflict refusal, counters,
  invoiceable quantity, invoice-deletion status roll-back, delete cascades.
- `test/workbook_transfer_test.dart` — the data import. *(Removed with the
  importer.)*

### Cleanup done

Google Sheets is gone: `SheetsService`, `WorkbookTransfer`, the Settings import
action, the `StorageBackendKind` switch, and the `google_sign_in` / `googleapis`
dependencies have all been removed. `OneDriveExcelService` is the only backend.
Sheets-era naming went with it (`tabName` → `tableName`,
`sheetsService` → `store`).

There is therefore **no rollback path** — a problem on a real device has to be
fixed forward. That was an explicit instruction, not an oversight.

### Still to do (needs a real account / device)

1. Create the Azure app registration and build with
   `--dart-define=MS_CLIENT_ID=...`. Until then sign-in cannot work — the app
   detects the placeholder client id and says so.
2. Confirm the redirect actually returns to the app on a device. The scheme
   must match in three places: `MicrosoftAuth.redirectScheme`, the
   `<data android:scheme>` in AndroidManifest.xml, and the Azure redirect URI.
   **A URI scheme cannot contain an underscore** — the application id is
   `com.example.success_erp`, so the natural "mirror the package name" scheme
   is illegal and `Uri.parse` throws, making sign-in impossible to complete.
   That bug was caught by a test; the scheme is `msauth.com.example.successerp`.
3. Run the §9 five-reopen check on a real signed-in device.

### If old Google Sheets data still needs importing

The importer was deleted, not lost. Recover `sheets_service.dart` and
`workbook_transfer.dart` from git history, wire them into Settings as before,
import once, then delete them again. `WorkbookTransfer` is idempotent (a
destination table that already holds data is skipped), so a repeated run cannot
duplicate the dataset.
