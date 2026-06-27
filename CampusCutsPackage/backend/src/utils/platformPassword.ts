/**
 * Normalizes Postgres `has_platform_password` and Apple linkage for API + account deletion.
 * Legacy rows may have `has_platform_password` NULL while `apple_sub` is set; treat like FALSE.
 */

export function hasExplicitPlatformPassword(value: unknown): boolean {
  if (value === true) return true;
  if (value === false || value == null) return false;
  if (typeof value === 'string') {
    const s = value.trim().toLowerCase();
    return s === 't' || s === 'true' || s === '1';
  }
  if (typeof value === 'number') return value === 1;
  return false;
}

export function isAppleLinkedAccount(row: { apple_sub?: unknown }): boolean {
  const s = row.apple_sub;
  if (s == null) return false;
  return String(s).trim().length > 0;
}

/** `needsPlatformPassword` / `needs_platform_password` in JSON responses. */
export function needsPlatformPasswordFromUserRow(row: {
  apple_sub?: unknown;
  has_platform_password?: unknown;
}): boolean {
  if (!isAppleLinkedAccount(row)) return false;
  return !hasExplicitPlatformPassword(row.has_platform_password);
}

/** DELETE /users/:id — omit body password only for Apple SSO without an explicit platform password. */
export function mayOmitPasswordForAccountDeletion(row: {
  apple_sub?: unknown;
  has_platform_password?: unknown;
}): boolean {
  return needsPlatformPasswordFromUserRow(row);
}
