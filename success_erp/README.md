# Order Fulfillment & Billing Manager

A lightweight ERP Flutter app for managing Customers, Products, Purchase Orders, Delivery Notes, and Invoices — using Google Sheets as the data store.

## Setup (5 minutes, no Firebase, no SHA-1)

### 1. Create a Google Cloud Project

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a new project (or use an existing one)

### 2. Enable APIs

1. Go to **APIs & Services > Library**
2. Enable **Google Sheets API**
3. Enable **Google Drive API**

### 3. Create a Web OAuth Client ID

1. Go to **APIs & Services > OAuth consent screen**
2. Choose **External**, fill in app name + your email, save
3. Add scope: `https://www.googleapis.com/auth/drive.file` (or skip — it's requested at runtime)
4. Add your Google email as a **Test user**
5. Go to **APIs & Services > Credentials**
6. Click **Create Credentials > OAuth client ID**
7. Choose **Web application**
8. Give it a name (e.g. "ERP App")
9. Click **Create** — copy the **Client ID**

### 4. Paste the Client ID into the App

Open `lib/core/services/sheets_service.dart` and replace:

```dart
static const String _webClientId = 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';
```

with the Client ID you just copied.

### 5. Run the App

```bash
flutter pub get
flutter run
```

On first launch:
1. Tap "Sign in with Google"
2. Sign in with your Google account
3. The app creates a spreadsheet named **ERP_App_Data** in your Drive with all 9 tabs
4. A round-trip test writes a test customer and reads it back
5. You land on the Dashboard

### 6. Verify

Open your Google Drive — you should see **ERP_App_Data** with tabs: Customers, Products, PurchaseOrders, PurchaseOrderItems, DeliveryNotes, DeliveryNoteItems, Invoices, InvoiceItems, Counters.

## Tech Stack

- **Flutter** (latest stable)
- **google_sign_in** + **googleapis** (Sheets API v4)
- **Riverpod** (state management)
- **GoRouter** (navigation)
- **PDF** + **Printing** (document generation)
- **shimmer** (skeleton loading)
- **share_plus** (CSV export)

## Features (Phases 1–8)

| Phase | Feature |
|-------|---------|
| 1 | Google Sign-In, spreadsheet creation, round-trip test |
| 2 | Customer CRUD (list, detail, form, search, empty state) |
| 3 | Product CRUD (list, form, search by name/SKU) |
| 4 | Purchase Orders (create with line items, counter helper, status tracking, referential integrity) |
| 5 | Delivery recording (PO item updates, status recalculation, DN PDF) |
| 6 | Invoice generation (partial invoicing, tax calculation, invoice PDF) |
| 7 | Dashboard (summary cards), Reports (4 tabs with CSV export), Drawer navigation |
| 8 | Per-row optimistic locking (conflict detection + dialog) |

## Data Model

| Tab | Key Columns |
|------|-------------|
| Customers | customer_id, name, phone, email, address, gst_number |
| Products | product_id, name, sku, unit, price, tax_percent |
| PurchaseOrders | po_id, po_number, customer_id, order_date, status |
| PurchaseOrderItems | po_item_id, po_id, product_id, quantity, rate, delivered_qty, pending_qty |
| DeliveryNotes | dn_id, dn_number, po_id, delivery_date |
| DeliveryNoteItems | dn_item_id, dn_id, po_item_id, delivered_qty |
| Invoices | invoice_id, invoice_number, po_id, invoice_date, total_amount, tax_amount, status |
| InvoiceItems | invoice_item_id, invoice_id, product_id, quantity, rate, tax_percent, amount |
| Counters | entity_name, last_number |
