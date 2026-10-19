# CabinetPro

CabinetPro is an appointment and patient management app for private clinics in Morocco. Phase 1 establishes the Next.js application, Supabase schema, tenant security, authentication, and clinic onboarding.

## Supabase setup

1. Install the Supabase CLI and Docker, then run `supabase init` only if this repository does not already contain Supabase config.
2. Start the local stack with `supabase start`.
3. Copy `.env.example` to `.env.local`, then fill in the URL and anon key printed by `supabase status`. Keep `SUPABASE_SERVICE_ROLE_KEY` server-only; never expose it through a `NEXT_PUBLIC_` variable.
4. Apply migrations with `supabase db reset` (local, destructive to the local database) or `supabase migration up` against the configured project. For a linked hosted project, use `supabase link --project-ref <project-ref>` and then `supabase db push` after reviewing the migration.
5. Run the tenant isolation check against the disposable local database:

   ```powershell
   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/tenant_isolation.sql
   ```

   The SQL creates two tenants, verifies cross-tenant reads and writes are blocked, verifies secretary role changes are blocked, and rolls back its fixtures.

`create_clinic(...)` atomically inserts a clinic and its owner membership. Invitations are persisted by trusted server code and accepted with `accept_clinic_invitation()` after the invited user authenticates; role and clinic are sourced from the server-created invitation, never user metadata. Each auth user can be a member of one clinic only.

## Environment variables

See `.env.example`. The service role key must only be read in server-only code and must never be sent to a browser.

## Run the app

Install dependencies and run the development server with `npm install` and `npm run dev`. The app uses the Next.js App Router and TypeScript.
