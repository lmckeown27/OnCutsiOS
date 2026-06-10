-- One-time cleanup: rows created before client/backend relay-name improvements used
-- first_name = 'Apple', last_name = 'User' for Hide My Email. Replace with relay local-part
-- and a neutral last name. This does not invent a legal name; users get real names from
-- the next Sign in with Apple when the app sends firstName/lastName from Apple / Keychain.

UPDATE users
SET
  first_name = COALESCE(
    NULLIF(TRIM(SPLIT_PART(LOWER(TRIM(email)), '@', 1)), ''),
    first_name
  ),
  last_name = 'Customer'
WHERE
  apple_sub IS NOT NULL
  AND LOWER(TRIM(email)) LIKE '%@privaterelay.appleid.com'
  AND TRIM(COALESCE(first_name, '')) = 'Apple'
  AND TRIM(COALESCE(last_name, '')) = 'User';
