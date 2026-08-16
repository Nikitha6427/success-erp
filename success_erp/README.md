# Order Fulfillment & Billing Manager

A Flutter Android app covering the Order-to-Cash cycle for a job-work /
metal-fabrication business: **Customer → Product → Purchase Order → Delivery
Note → Invoice → Reports**.

**`AGENTS.md` is the source of truth for behaviour.** This file only covers
setup and layout.

## Storage backend

**Microsoft OneDrive.** A single Excel workbook, `ERP_App_Data.xlsx`, in the
app's own OneDrive folder (app-folder scope only — the app cannot see the rest
of your OneDrive). One worksheet per entity, each a real Excel Table, accessed
through Microsoft Graph's table/row endpoints.

Rows are read and written through the table's own header row, so adding a column
never shifts existing data and older workbooks keep working: unknown columns are
appended to the header on first run and missing values read back as empty.

OneDrive is the only backend — the earlier Google Sheets implementation has been
removed. Swapping clouds again would mean one new `WorkbookStore` +
`StorageBackend` implementation and one changed provider in `lib/app.dart`;
nothing above the repository layer knows which cloud it talks to.
See AGENTS.md §2 and §12.

## Setup

### 1. Register the app with Microsoft

1. [Azure Portal](https://portal.azure.com) → **Microsoft Entra ID** → **App
   registrations** → **New registration**.
2. Name it anything. Under **Supported account types** choose
   *Accounts in any organizational directory and personal Microsoft accounts*
   (this matches the `common` tenant the app uses).
3. **Register**, then go to **Authentication** → **Add a platform** →
   **Mobile and desktop applications** → **Custom redirect URI**:

   ```
   msauth.com.example.successerp://auth
   ```

   This string must match `MicrosoftAuth.redirectUri` and the
   `<data android:scheme>` in `android/app/src/main/AndroidManifest.xml`
   exactly. Note there is **no underscore** — a URI scheme cannot contain one.
4. Confirm **Allow public client flows** is enabled (Authentication → Advanced
   settings). The app is a public client and uses PKCE, with no secret.
5. **API permissions** → **Microsoft Graph** → *Delegated* →
   `Files.ReadWrite.AppFolder` and `offline_access`. `offline_access` is not
   optional: it is what issues the refresh token that keeps you signed in
   across restarts.
6. Copy the **Application (client) ID** from the Overview page.

### 2. Run

```bash
flutter pub get
flutter run --dart-define=MS_CLIENT_ID=<your-application-client-id>
```

The client id is read at build time, so it is not committed. Building without
it leaves a placeholder and sign-in will fail.

On first launch, sign in with Microsoft. The app creates `ERP_App_Data.xlsx` in
its OneDrive app folder with one worksheet and Excel Table per entity, and lands
on the Dashboard. Afterwards the session is restored silently — see AGENTS.md §9
for why that path is load-bearing and how it is tested.

Fill in **Settings → Company Profile** before printing anything: it is the
letterhead on every Delivery Note and Invoice.

## Layout

```
lib/
  app.dart                     startup stages, routing, provider wiring
  core/
    repository/                BaseRepository: row index + optimistic locking
    services/
      storage_backend.dart     auth contract the startup flow depends on
      counter_helper.dart      PO/{S|L}{FY}/{seq} and simple sequences
      invoice_math.dart        invoiceable qty, totals, PO status  (pure)
      number_to_words.dart     Indian lakh/crore amount in words   (pure)
      address_format.dart      address line assembly, "None/Blank" (pure)
      pdf_common.dart          shared letterhead / party boxes / copies
      pdf_share.dart           writes each copy as its own PDF file to share
      workbook_store.dart      backend-neutral schema + row interface
      onedrive_excel_service.dart  OneDrive/Graph backend (active)
      microsoft_auth.dart      PKCE sign-in + silent refresh
      secret_store.dart        keystore-backed refresh-token storage
      blank_workbook.dart      builds a minimal valid .xlsx to upload
    theming/, widgets/         ColorScheme, status pill, empty state, skeletons
  features/<entity>/           model, repository, providers, screens, pdf
```

No UI or business logic touches a cloud API directly — everything goes through a
repository over `WorkbookStore`, which is why swapping the backend was a
one-constant change rather than a rewrite.

## Tests

```bash
flutter test
```

| File | Covers |
|------|--------|
| `session_persistence_test.dart` | Five consecutive cold starts with zero Sign-In flash, plus every failure mode that must *not* show Sign-In (AGENTS.md §9) |
| `invoice_math_test.dart` | Invoiceable vs pending quantity, zero-rate lines, CGST/SGST splits, PO status transitions |
| `number_to_words_test.dart` | Indian numbering, paise rounding, large amounts |
| `counter_helper_test.dart` | Financial-year derivation and per-(category, FY) PO sequences |
| `delete_test.dart` | Single and bulk delete across customers, products, POs and invoices: cascades, invoice protection, PO status roll-back, partial batches, referential integrity |
| `onedrive_store_test.dart` | Workbook/table setup, app-folder-only access, row addressing, blank-in-place deletes, Graph throttling |
| `onedrive_session_test.dart` | §9 re-proved on the Microsoft auth stack: 5 cold starts, offline/locked-keystore vs revoked-token, scope discipline |
| `onedrive_repository_test.dart` | Repository layer and business logic driven over the real OneDrive service |
| `pdf_copies_test.dart` | Three separate single-page PDFs per document, file naming, Latin-1 safety |
| `schema_test.dart` | Every model writes exactly its declared columns; old rows still read |
| `address_format_test.dart` | Printed address assembly and "None/Blank" |
