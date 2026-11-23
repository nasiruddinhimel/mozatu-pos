# MOZATU Web POS

A deployable online POS foundation for MOZATU using Vite + React + Supabase.

## Included
- Email/password login (Supabase Auth)
- Product & raw-material register
- Purchase recording with raw-stock increase
- Sales recording, optional recipe-based COGS and raw-stock deduction
- Recipe setup
- Operating expenses
- Monthly sales / purchase / COGS / gross profit / net profit report
- JSON backup download and restore
- PostgreSQL schema with row-level security

## Important accounting treatment
Purchases increase inventory and are shown as cash/stock acquisition. They are not deducted again as operating expenses. COGS is recorded when goods are sold/consumed. Gross profit = sales - COGS. Net profit = gross profit - operating expenses.

## Setup
1. Create a Supabase project.
2. In Supabase SQL Editor, run `supabase/schema.sql`.
3. Copy `.env.example` to `.env` and enter your Supabase Project URL and anon/publishable key.
4. Run `npm install`, then `npm run dev`.
5. Create the first user in Supabase Authentication > Users.
6. Deploy to Vercel and connect your own domain in Vercel Project Settings > Domains.

Never put the Supabase service-role key in browser code. Only use the anon/publishable key.

## Existing local POS data
In the existing MOZATU HTML POS, use **Download Full Backup** to export a `.json` file. The Web POS includes an import helper placeholder; full migration should be run after reviewing the backup data and mapping existing transactions to the new normalized tables. Do not delete the old browser data until migration is verified.

## Production note
This is a deployable starter, not yet a live website. Hosting and domain activation require your own Supabase, Vercel and domain-provider accounts. Do not share passwords or secret keys in chat.
