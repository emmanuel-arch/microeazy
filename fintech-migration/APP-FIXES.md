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

| File | Change |
|---|---|
| `src/lib/realm.js` | **New.** A cutover guard — see below |
| `src/main.jsx` | Calls `enforceRealm()` before React renders |
| `.env` | Dev entity `3002` → `3005`, matching `.env.production` |

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

### Verify — I built it and checked the output

```
42 × https://micromartafrica.co.ke     (was 42 × live.testapps.co.ke)
 0 × testapps
 entity 3005, apiRealm present
```

### Ship

`npm ci && npm run build`, then deploy `dist/` to the `pwa.servicesuitecloud.com`
project. **Check the Vercel dashboard env vars before building there** — this is
the same class of fault as §1: a dashboard value overrides `.env.production`
silently. `VITE_ENTITY_ID` must be `3005` or absent, never empty.

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

### Not fixed, and deliberately

From the 2 September channel analysis: **F1** (the category menu reads a global
table with no entity column — needs a schema decision), **F4** (no multi-book
branch at level 5), **F5** (lender selection not scoped to the operator's own
entities), **F7** (the KES 3,000 minimum enforced in SQL and discarded in C#),
**F8** (the endpoint is unauthenticated and the PIN has no attempt limit).

**F8 is the one I would do next.** A 4-digit PIN with no lockout, on an
unauthenticated URL, is brute-forceable by anyone who can reach it.

### ⚠ Confirm before deploying

The channel analysis describes the dial string as `*384*NNNN#`. You dial
`*483*490#`. Those are different service codes and I could not verify from here
which deployment answers yours. Fixing the wrong one would look like fixing
nothing.

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
