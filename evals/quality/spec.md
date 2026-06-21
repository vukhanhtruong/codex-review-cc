# Design Spec: Password Reset via Email

## Problem Statement

Users who forget their password currently have no self-service way to regain
access to their account; they must contact support, which is slow and costly.
We need a secure, self-service flow that lets a user reset their password using
a link sent to their registered email address.

## Functional Requirements

1. A user can request a password reset by submitting their email address.
2. If the email matches a registered account, the system sends an email
   containing a reset link with a unique token.
3. The user clicks the link, lands on a reset form, and enters a new password.
4. On valid submission, the password is updated and the user can log in with
   the new credentials.
5. The reset token is single-use and time-limited.
6. After a successful reset, the user is notified by email that their password
   changed.

## User Flow

1. User clicks "Forgot password?" on the login screen.
2. User enters their email and submits.
3. System shows a confirmation message ("If an account exists, you'll receive
   an email").
4. User opens the email and clicks the reset link.
5. User is taken to a reset form, enters and confirms a new password.
6. System validates the token and the password, updates it, and redirects to
   login with a success message.

## API Endpoints

### POST /api/auth/password-reset/request
Request a reset email.
```
Request:  { "email": "user@example.com" }
Response: 200 { "message": "If an account exists, an email has been sent." }
```

### POST /api/auth/password-reset/confirm
Submit a new password with the token.
```
Request:  { "token": "<reset-token>", "newPassword": "<password>" }
Response: 200 { "message": "Password updated successfully." }
          400 { "error": "Invalid or expired token." }
```

## Data Model

`password_reset_tokens`
- `id`
- `user_id`
- `token_hash`
- `expires_at`
- `used_at` (nullable)
- `created_at`

## Acceptance Criteria

- AC1: Submitting a registered email sends a reset email containing a link.
- AC2: Submitting an unregistered email returns the same generic response and
  sends no email.
- AC3: Clicking a valid link and submitting a new password updates the password.
- AC4: An expired token is rejected with a 400 error.
- AC5: A token cannot be reused after a successful reset.
- AC6: The user receives a confirmation email after a successful reset.
- AC7: The new password must meet the password policy (min 8 characters).
