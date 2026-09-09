# App-side fixes — what changed, how to verify, how to ship

The database work is in the numbered SQL scripts beside this file. This is the
other half: the four application defects found in the same investigation.

Nothing here is deployed. Every change is on disk, typechecked and built.
`git` refuses to run in these repos on this machine ("dubious ownership", a
pre-existing SID problem), so committing and deploying are yours.

---

## 1 · The OTP 400, and the code that was never sent

### What was actually wrong

Two separate faults, and fixing either one alone leaves the customer stuck.

**The 400.** I pulled the live bundle from `portal.servicesuitecloud.com` and
read it. It sends `lenderSlug: ""` on every call:

```js
const vo = "", bo = n => JSON.stringify({ lenderSlug: vo, nationalId: n })
```

`VITE_LENDER_SLUG` is **set but empty** in that build's environment. Vite inlines
it as `""`, and the code read `import.meta.env.VITE_LENDER_SLUG ?? "micromart"` —
`??` only catches `null` and `undefined`, so the default never fired. Twelve
borrower routes resolve the lender from that field; all twelve answered
400 "Choose a lender".

**The silence behind it.** Even with the right slug the endpoint returns
`delivered: false`. `hasSmsProvider()` finds nothing: Micromart have no SMS
config in our vault and the platform Africa's Talking key is unset. Setting the
platform key would make codes arrive — under *our* sender ID, which is the wrong
fix. A verification code from a name the customer has never dealt with is
indistinguishable from a phishing attempt.

### What changed

| File | Change |
|---|---|
| `micro-eazy-app/src/lib/api/portal.ts` | `??` → `\|\|` with `.trim()`, so an empty or whitespace env value falls through to the default |
| `connected-suite/src/lib/tenancy.ts` | A blank slug resolves to `PORTAL_DEFAULT_LENDER_SLUG`. A **fallback, never an override** — a request that names a lender still gets that lender |
| `connected-suite/.env` | `PORTAL_DEFAULT_LENDER_SLUG="micromart"` |
| `connected-suite/src/lib/sms/servicesuite.ts` | **New.** Queues the message in the lender's own `Notifications.dbo.SMS` with their `EntityId` |
| `connected-suite/src/lib/sms/send.ts` | Provider order is now vault → **ServiceSuite outbox** → platform Africa's Talking |

The SMS fix is modelled on `sp_restBorrowerPin`, which is how Micromart's own
system sends every message it sends:

```sql
INSERT INTO Notifications.dbo.SMS
  (smsMessage, smsto, EntityId, CreateDate, isSent, ScheduleDate, SmsProviderId)
VALUES (@msg, @to, @entity, GETDATE(), 0, GETDATE(), 5)
```

**The sender ID is a property of the entity, not of the calling app.** Their
queue drainer looks up the entity's Africa's Talking credentials and sends under
the sender ID registered to them. Writing the row with `EntityId = 3005` is
therefore the entire fix — there is no sender to configure on our side.

### ⚠ This one needs something from you

The insert is a **write**, and Micromart's SQL has no public route, so it goes
over the relay — which refuses writes unless `SQL_RELAY_ALLOW_WRITES=true` is set
**on the relay host**. Until it is armed, `serviceSuiteOutbox()` returns null and
`sendSms` falls through to the next provider rather than pretending. No code
change gets around that, and it should not: an unarmed relay is a deployment that
has not been given permission to write to a lender's live database.

### Verify

```bash
# Before: 400 "Choose a lender". After: 200.
curl -s -X POST https://portal.servicesuitecloud.com/api/portal/otp \
  -H 'Content-Type: application/json' -d '{"phone":"254758517032"}'

# And with the relay armed, delivered should be true.
```

---

## 2 · The PWA on the wrong platform

`pwa.servicesuitecloud.com` serves a build whose **42 API calls all point at
`https://live.testapps.co.ke`** — the shared platform on `213.148.17.198` — with
`EntityId: 7`. That is why your password reset arrived from "SERVICE SUITE TEST
AREA" under Techcrast's sender ID and landed in the `.198` database, and why the
products on screen were Salary Advance / Weekly Business Loan / 4 weeks Product
rather than Micromart's shelf.

`C:\GIT\micromart-client-pwa` was already correct. It had never been deployed.

### What changed

### One book was the wrong shape

My first pass pinned the build to 3005. That was wrong, and it would have locked
out every Micromart Africa customer. **This app serves both books**, and which
one a customer is on is a fact about the customer, not about the build.

The original brief said exactly this: look the customer up, in both → contact
admin, in one → scope to it, in neither → register.

It also turned out that correcting `VITE_ENTITY_ID` could never have worked.
Four screens — **Login, Password, Register and Settings** — never imported
`lib/entity` at all. Each carried its own `const entityId = "3002"`. Sign-in was
pinned to the field book no matter what any env file said, which is why a
Fintech customer could not log in and why a Fintech password reset went nowhere.

| File | Change |
|---|---|
| `src/lib/entity.js` | Rewritten. `MICROMART_ENTITIES` (the books to search), `DEFAULT_ENTITY_ID` (pre-sign-in branding only), `REGISTRATION_ENTITY_ID` (where a new customer joins). Three ideas that were previously one number |
| `src/lib/signin.js` | **New.** `signInAcrossBooks()` probes every book in parallel and returns `ok` / `ambiguous` / `none` / `unreachable`. `resetPasswordAcrossBooks()` walks them **one at a time** |
| `src/lib/session.js` | **New.** The session now carries `entityId`; `activeEntityId()` is the single reader |
| `src/pages/Login.jsx` | Uses the probe. Both books → "contact our office". Neither → the API's own message. Unreachable → says so |
| `src/pages/Password.jsx` | Uses the sequential reset. Also now *shows* failures — it used to log to the console and leave a stopped spinner |
| `src/pages/Settings.jsx` | Change-password targets the signed-in customer's book |
| `src/pages/Register.tsx` | New registrations join `REGISTRATION_ENTITY_ID` (3005) |
| `Loan.jsx`, `LoanApplication.jsx`, `notificationPermission.js`, `App.jsx` | Read `activeEntityId()` instead of a build constant |
| `src/lib/realm.js` | **New.** A cutover guard — see below |
| `src/main.jsx` | Calls `enforceRealm()` before React renders |
| `.env`, `.env.production` | `VITE_ENTITY_ID` → `VITE_ENTITY_IDS=3002,3005` + `VITE_REGISTRATION_ENTITY_ID=3005` |

**Why the reset path is sequential.** Login has no side effect, so asking both
books at once is free. Reset mints a password and sends an SMS — a parallel
probe would send a dual-book customer two different passwords with no way to
tell which is which. It stops at the first book that answers.

That does mean a genuinely dual-book customer is reset on the first book only
and never learns they are on two. Detecting that without a side effect needs an
account-existence endpoint the API does not have. It is transitional: scripts 04
and 05 remove the case itself, which is the real fix.

**Why the realm guard matters more than it looks.** This is a backend swap on
devices that are already installed. Every customer's `localStorage` holds a
`session` minted by `live.testapps.co.ke`, and a `configuration` containing
`{ EntityId: 7, EntityName: "SERVICE SUITE TEST AREA" }` — including the other
company's logos and brand colours. Deploying without clearing that shows
returning customers the wrong company's branding and a session that fails every
call. Worse: if the config refetch fails, entity 7 stays pinned in storage on a
build that now talks to Micromart.

`realm.js` stamps storage with `micromartafrica.co.ke|3005` and wipes everything
this app owns when the stamp does not match. Customers sign in once more, on
first open. That is the correct trade.

### Verify — built and checked

```
41 × https://micromartafrica.co.ke   (was 42 × live.testapps.co.ke)
 0 × testapps
 0 × hard-coded "3002" / "3005" outside lib/entity.js
 [3002,3005] present, apiRealm present, "exists on both" copy present
```

`eslint` is clean on all four new files. The rest of `src/` carries pre-existing
lint debt (25 problems in four files nobody touched here); I did not widen it.

### Ship

`npm ci && npm run build`, then deploy `dist/` to the `pwa.servicesuitecloud.com`
project. **Check the Vercel dashboard env vars before building there** — this is
the same class of fault as §1: a dashboard value silently overrides
`.env.production`. `VITE_ENTITY_IDS` must be `3002,3005` or absent — and the old
`VITE_ENTITY_ID` (singular) should be **deleted** from the dashboard, because it
no longer means anything and will mislead the next person who reads it.

---

## 3 · The USSD service

Your PIN went in and the gateway said "technical problems". That text is Africa's
Talking's own — it is what a subscriber sees when the callback returns anything
other than 200 with a CON/END body. `ServiceController` had **no exception
handler at all**, so every throw became a 500 with nothing in the log.

### What changed

| File | Change |
|---|---|
| `ServiceController.cs` | Outermost `try/catch` on `HandleUssd`. Every failure is now a 200 carrying an END the customer can act on, and the real reason goes to `ILogger` + the session log |
| `ServiceController.cs` | Entity resolved **once**, at the top, and threaded down — instead of re-derived at four call sites by two different rules |
| `ServiceController.cs` | Five `entityId <= 0` guards. Entity 0 is not a book; querying products or balances under it returned an empty menu that read as a broken service |
| `ServiceController.cs` | PIN setup refuses for a customer we cannot place on one book, with an explanation, instead of overwriting every book |
| `ServiceController.cs` | A 4-digit PIN check. `int.TryParse("0421")` gives 421, hashed as `"421"` — a PIN that can never be entered again |
| `Login.cs` | Every PIN read and write takes an entity. `SetPin` **refuses** when it is unknown rather than updating every matching row |
| `Login.cs` | `BCrypt.Verify` wrapped: a malformed hash is a wrong PIN, not a 500 |
| `Login.cs` | A 50-character hash reads as "no PIN set", routing those 40 customers into the set-a-PIN screen |
| `Login.cs` | `CheckCustomerExists` / `SessionLevel` handle `DBNull` instead of throwing `InvalidCastException` |
| `GetEntityId.cs` | Deterministic `ORDER BY`, closed accounts excluded, `DBNull` safe |
| `writelog.cs` | **A singleton opening a file with `FileShare.Read` on every keypress.** Two customers dialling at the same moment: `IOException`, unhandled, 500. Now locked, `FileShare.ReadWrite`, and swallowed — logging must never be why a session dies |

`dotnet build` — 0 warnings, 0 errors.

### F1 — the four dead ends — also fixed

The category menu was `SELECT ID, CategoryName FROM ProductCategories`, with no
filter at all. That table has **no EntityId column**, so every customer of every
company saw all six entries. For a Fintech customer, read live on 9 September:

| | Category | Fintech products |
|---|---|---|
| 1 | BUSINESS LOAN-DAILY | 0 |
| 2 | BUSINESS LOAN-WEEKLY | 1 |
| 3 | BUSINESS LOAN-MONTHLY | 1 |
| 4 | SCHOOL FEES LOAN | 0 |
| 5 | SALARY LOAN | 0 — and 0 on *every* book |
| 6 | ASSET LOAN | 0 — and 0 on *every* book |

Four of six were dead ends. No schema change was needed after all: the menu now
applies the **same predicate `sp_ussdGetproducts` applies** — entity, active,
USSD-enabled, and the borrower's own branch via `EntityUnits` — so the menu and
the list it leads to cannot disagree, and a category that would render an empty
screen never appears. An entirely empty shelf now says so instead of showing a
header with nothing under it.

### F8 — brute force — fixed, in two halves

| | |
|---|---|
| `Models/PinAttemptLimiter.cs` | **New.** 5 wrong PINs in 15 minutes holds that number for 15 minutes. Checked *before* the bcrypt comparison, so a held number costs an attacker a dictionary lookup rather than a deliberately expensive hash — otherwise the defence is its own denial-of-service |
| `ServiceController.cs` | Optional shared secret on the callback URL. Register it as `https://<host>/ussd/service?k=<secret>` and set `Ussd:CallbackSecret` to match |

Two deliberate choices worth knowing:

- **It holds the attempt, not the account.** Locking a customer's record on
  failed attempts against an unauthenticated endpoint hands anyone a way to lock
  every customer out by dialling their numbers wrong five times.
- **The secret is opt-in.** Unset, nothing is enforced and behaviour is
  unchanged. Mandatory would mean a deploy that forgot the config takes the
  whole channel down for real customers — and a security control that causes an
  outage gets switched off, after which you have neither.

The tally is in memory, so a restart clears it and two instances behind a load
balancer each keep their own. That stops the attack that matters — a sustained
run against one number — without a schema change on a live lender's database.

### Still not fixed

**F4** (no multi-book branch at level 5) and **F5** (lender selection not scoped
to the operator's own entities) — both only affect customers on more than one
book, and scripts 04 and 05 remove that population. **F7**, the KES 3,000
minimum enforced in SQL and discarded in C#, is the one with real money behind
it: a KES 2,000 application is confirmed to the customer and silently dropped.

### What remains for any of this to take effect

The code is pushed (`skegode/ATusersUssdApI@cf8f22f` and the F1/F8 work after
it). None of it is running yet. In order:

1. **Confirm `*483*490#` reaches this deployment.** The 2 September channel
   analysis describes the dial string as `*384*NNNN#`; you dial `*483*490#`.
   Those are different service codes. Check the Africa's Talking dashboard for
   which callback URL that code posts to, and that it is this service. Fixing
   the wrong deployment looks exactly like fixing nothing.

2. **Publish and copy.** `dotnet publish -c Release`. The repo's publish profile
   targets `C:\Users\Sharon Chepchumba\Desktop\AtUssd`, i.e. someone builds to a
   folder and copies it onto the host by hand — so whoever owns that machine has
   to do this, or the profile needs repointing at the real target.

3. **Do not overwrite `appsettings.json` on the server.** It is **gitignored**,
   so the production `dbConnectionString` exists only on that host and is not in
   the repository. A publish that copies the whole folder over the top will
   delete it, and the service will then answer every dial with the new generic
   error — which is at least a message rather than a 500, but it is still down.

4. **Restart the app pool / service.** .NET caches nothing across a restart, but
   the old assembly stays loaded until one happens.

5. **Optional, and recommended:** set `Ussd:CallbackSecret` in `appsettings.json`
   and append `?k=<secret>` to the callback URL registered with Africa's Talking.
   Do both or neither — the secret is only enforced when it is set, but once set
   a callback without it gets a 404.

6. **Run [`09-ussd-product-menu.sql`](09-ussd-product-menu.sql)** so Micro Chap
   Chap can appear at all. It is a data fault, not a code one: `CategoryId` and
   `UssdOrder` are both NULL, and neither the menu query nor the selector can
   match a NULL.

Script `07-repair-broken-pins.sql` is now **optional**. The code change already
treats a hash that is not 60 characters as "no PIN set", so those 40 customers
are routed into the set-a-PIN screen without it. Running it still tidies the
data, and costs nothing.

### Then dial it

Your own record is ready: borrower **170497**, entity 3005, unit 129, exactly
one row for `254758517032`, and a valid 60-character `$2b$` hash. So
`ResolveEntity` returns 3005 and the fintech shelf is what you will see.

**Your PIN is `1765`** — set by the reset at 12:08 on 8 September (outbox row
2791806). `6836` is from July 2024 and `9409` from 29 August; both are long
dead, which is why the PIN screen was never going to let you past even before
the crash.

---

## 4 · Sign-in and the demo account

Sign-in was **already wired** — `SignIn.tsx` drives `requestCode` / `submitCode`
/ `identify` through `session.tsx`, and `/api/portal/enrolment` scopes its
borrower lookup with `WHERE b.EntityId = @entityId`, which is 3005.
`DEPLOY.md`'s "sign-in is absent" note is out of date.

It was blocked entirely by §1. With the slug fixed and the relay armed, it works.

**You already have a usable account.** Borrower **170497** — Emmanuel Birgen,
`254758517032`, national ID `39362808` — is on 3005 in unit 129. Phone, SMS code,
national ID, and you are in.

For a *separate* demo account to hand to someone else, run
[`08-demo-account.sql`](08-demo-account.sql). Set the phone to a handset you hold
(sign-in sends a real OTP) and a national ID unused on both books. It creates the
borrower under Geoffrey's office in unit 129 with **no credentials** — BCrypt
cannot be computed in T-SQL, so the customer dials `*483*490#` once and sets
their own PIN, which then works on both USSD and the app.

---

## Order to ship

1. **Arm the relay** (`SQL_RELAY_ALLOW_WRITES=true` on the relay host) — §1's SMS
   leg and the dormancy service both need it.
2. **Deploy connected-suite** with `PORTAL_DEFAULT_LENDER_SLUG=micromart`. The
   portal stops 400ing immediately, even for handsets still on the old bundle.
3. **Deploy micro-eazy-app** — the slug fix, so new bundles are correct at source.
4. **Deploy micromart-client-pwa** over `pwa.servicesuitecloud.com`, after
   checking the dashboard env vars.
5. **Deploy ATusersUssdApI**, once you have confirmed `*483*490#` routes to it.

Steps 2 and 3 are independent and either order works — the server-side fallback
and the client-side default are each sufficient on their own, which is the point
of having both.
