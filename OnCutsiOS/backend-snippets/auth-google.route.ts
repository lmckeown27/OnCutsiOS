/**
 * Add to OnCuts backend (deployed repo) so Intera POST /api/v1/auth/google works.
 *
 * 1) npm deps: `google-auth-library` (already in OnCuts backend).
 * 2) Env (EC2/pm2): set at least one audience your tokens use:
 *    - GOOGLE_OAUTH_IOS_CLIENT_ID = iOS OAuth client ID (same as GoogleService-Info CLIENT_ID)
 *    - GOOGLE_OAUTH_WEB_CLIENT_ID = web client (optional if you only use iOS)
 *    You can also set VITE_GOOGLE_OAUTH_CLIENT_ID if that matches your tokens.
 * 3) In auth.routes.ts: `router.post('/google', googleIdTokenLogin);`
 * 4) In auth.controller.ts: paste the handler below (adjust imports: Request, OAuth2Client).
 */

import { Request, Response, NextFunction } from 'express';
import { OAuth2Client } from 'google-auth-library';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { logger } from '../utils/logger';
import { generateAccessToken, generateRefreshToken } from '../utils/jwt.utils';
import { resolveAccessTokenRole } from '../utils/access-token-role';

const googleOAuthClient = new OAuth2Client();

export const googleIdTokenLogin = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const rawBody = req.body as { idToken?: string; id_token?: string };
    const idToken = (rawBody.idToken ?? rawBody.id_token)?.trim();
    if (!idToken) {
      throw new ApiError(400, 'idToken required');
    }

    const audiences = [
      process.env.GOOGLE_OAUTH_IOS_CLIENT_ID,
      process.env.GOOGLE_OAUTH_WEB_CLIENT_ID,
      process.env.VITE_GOOGLE_OAUTH_CLIENT_ID,
    ]
      .map((s) => s?.trim())
      .filter((s): s is string => Boolean(s));

    if (audiences.length === 0) {
      logger.error('Google sign-in: set GOOGLE_OAUTH_IOS_CLIENT_ID and/or GOOGLE_OAUTH_WEB_CLIENT_ID');
      throw new ApiError(
        500,
        'Google sign-in is not configured on the server (set GOOGLE_OAUTH_IOS_CLIENT_ID and/or GOOGLE_OAUTH_WEB_CLIENT_ID)'
      );
    }

    let ticket;
    try {
      ticket = await googleOAuthClient.verifyIdToken({
        idToken,
        audience: audiences.length === 1 ? audiences[0] : audiences,
      });
    } catch {
      throw new ApiError(401, 'Invalid or expired Google token');
    }

    const gPayload = ticket.getPayload();
    if (!gPayload?.sub) {
      throw new ApiError(400, 'Invalid Google token payload');
    }

    const emailRaw = gPayload.email?.trim().toLowerCase();
    if (!emailRaw) {
      throw new ApiError(401, 'Google account has no email');
    }
    if (gPayload.email_verified === false) {
      throw new ApiError(401, 'Google email not verified');
    }

    const result = await pool.query(
      `SELECT id, email, first_name, last_name, "campusId", role, "isBlocked", "isBanned", email_verified, "avatarUrl", sui_address
       FROM users WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))`,
      [emailRaw]
    );

    if (result.rows.length === 0) {
      throw new ApiError(401, 'Account not found', 'ACCOUNT_NOT_FOUND');
    }

    const user = result.rows[0];

    if (user.isBlocked || user.isBanned) {
      throw new ApiError(403, 'Account is deactivated');
    }

    await pool.query('UPDATE users SET "lastActiveAt" = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);

    const barberCheck = await pool.query(
      'SELECT id FROM barbers WHERE "userId" = $1 AND "isActive" = true',
      [user.id]
    );
    const hasBarberProfile = barberCheck.rows.length > 0;

    const accessRole = await resolveAccessTokenRole(user.id, user.role);

    const token = generateAccessToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    const refreshToken = generateRefreshToken({
      userId: user.id,
      email: user.email,
      role: accessRole,
      campusId: user.campusId,
    });

    logger.info(`User logged in (Google): ${user.email} (jwtRole=${accessRole}, dbRole=${user.role})`);

    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.first_name,
          lastName: user.last_name,
          role: user.role,
          campusId: user.campusId,
          emailVerified: user.email_verified,
          profile_picture_url: user.avatarUrl,
          hasBarberProfile,
          suiAddress: user.sui_address ?? null,
        },
        accessToken: token,
        refreshToken,
      },
    });
  } catch (error) {
    next(error);
  }
};
