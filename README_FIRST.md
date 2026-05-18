# Hisabs v89.23 — OTP for signup, forgot password, change email

```
index.html: 88b9c6c578d6c8cf8776ecfcef1a03b3
Previous (v89.22): 36368808ccffa0bee667e170adc999a8
```

## ⚠️ READ THIS FIRST

**Before deploying v89.23, you must update 3 Supabase email templates.**
See `SUPABASE_SETUP_REQUIRED.md` for step-by-step instructions.

If you skip that step, users will receive emails with links (not codes)
and the OTP modal will sit waiting forever.

## What changed

### 1. Signup verification (OTP code at first signup only)

**Before**: User signs up → Supabase sends magic link → user clicks
link to confirm → returns to app → signs in.

**Now**: User signs up → Supabase sends 6-digit code → user types code
in a new OTP modal → signed in immediately. After this one-time
verification, normal password sign-in works forever.

### 2. Forgot password (OTP code → set new password)

**Before**: User taps "Forgot password" → enters email → magic link
sent → opens email → clicks link → sets new password in browser tab.

**Now**: User taps "Forgot password" → enters email → 6-digit code
sent → types code in OTP modal → "Set new password" modal appears →
types new password → signed in.

### 3. Change email (new feature)

**Before**: Not possible. Email field was disabled in Profile.

**Now**: Profile → Account → "Change" button next to email →
type new email → code sent to NEW email → type code → email updated.

## OTP modal UX features

- 6 single-digit boxes (auto-advance on input, backspace goes back)
- Paste a 6-digit code → fills all boxes at once
- Last digit auto-submits the code
- "Resend" link with 60-second cooldown
- Inline error messages (invalid code, expired, etc.)
- Mobile keyboard shows number pad (`inputmode="numeric"`)
- Autofill support for OTP from email apps (`autocomplete="one-time-code"`)

## Existing users — unaffected

If your account is already verified (Zeus, Kratos, Rajesh, anyone who
signed up before v89.23): nothing changes. You sign in with email +
password as always. Only NEW signups go through OTP verification.

## Verification

```
JS: OK
HTML comments: 42/42
CSS braces: 1963/1963
Backticks: 2138 (even)
Runtime smoke: clean

6 transforms applied + 1 patch
18 v89.23 feature checks pass
v89.22 features intact (3/3)
v89.21 features intact (2/2)
v89.20 features intact (2/2)
Auth integrity: signInWithPassword, onSupabaseSignedIn,
  openChangePasswordModal, checkAuthLockout, recordAuthFailure all preserved
Legacy magic-link resetPasswordForEmail: REMOVED (replaced with OTP)

File size: 1709 KB (was 1691 KB, +18 KB for OTP modal + flows)
```

## Deploy

**Before deploying, complete SUPABASE_SETUP_REQUIRED.md first.**

```bash
cd ~/Documents/GitHub/hisabs
cp ~/Downloads/hisabs_v89_23/index.html ./index.html
md5sum index.html
# expected: 88b9c6c578d6c8cf8776ecfcef1a03b3
```

Commit + push. **No SQL migrations** — OTP uses Supabase's built-in
auth flows; only the email template config needs to change.

## What to test after deploy

### Signup with OTP:
1. Sign out (if signed in)
2. Click "Create account" → enter name, email, password (use a NEW email)
3. Click Create → OTP modal appears
4. Check the new email's inbox → find the 6-digit code
5. Type the code → app should sign you in and load
6. Sign out → sign back in with the same email + password → should work normally

### Forgot password with OTP:
1. On sign-in screen, click "Forgot password?"
2. Type your email → click Send code
3. Check email → find code → type in OTP modal
4. After verification, "Set new password" modal appears
5. Type new password twice → Save → app loads with you signed in
6. Sign out → sign in with the NEW password → should work

### Change email:
1. Sign in → open Settings → Profile tab
2. Click "Change" button next to email
3. Type new email address → click Send code
4. Check the NEW email's inbox for the code
5. Type code → confirmation that email updated
6. Sign out → try to sign in with NEW email → should work (old email no longer valid)

### Edge cases to verify:
- Wrong code: modal shows error, allows retry
- Resend: link greys out for 60 seconds after sending
- Paste a 6-digit code: fills all boxes and auto-submits
- Cancel during OTP: returns to sign-in screen cleanly (no half-state)

## Honest limits

- **Cannot test runtime** — sandbox only verifies source structure. Real
  OTP flow works only against a configured Supabase instance with the
  email templates updated.
- **No retry limits on OTP** — Supabase enforces its own rate limit
  (default: 4 codes per hour). If a user requests too many, Supabase
  returns an error and our modal shows it. Not something I can fix
  client-side.
- **Code expiry** — Supabase OTP codes expire after 1 hour by default.
  Configurable in Authentication → Settings.
- **Account lockout doesn't apply to OTP flows** — the existing
  `checkAuthLockout` only gates `signInWithPassword`. OTP flows
  bypass that. Acceptable since OTP is rate-limited by Supabase itself.
- **Edge case: user verifies signup OTP but session is null** — should
  never happen in practice, but we throw an error and ask them to sign
  in normally.
- **iOS Safari OTP autofill** — should work via `autocomplete="one-time-code"`,
  but iOS's "fill from messages" is the most reliable. Email autofill
  on iOS is less reliable. User can always type the code manually.

## What's next?

If everything works, that completes the v89.21–v89.23 trio. Remaining
items from the original v89 list:
- Distribution row delete sound (small carry-over from v89.20)
- Instant cross-device sign-out (needs forced_signouts table)
- Orphan Steve business cleanup (harmless, separate concern)

Let me know what you'd like next.

