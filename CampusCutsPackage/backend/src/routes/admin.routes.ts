/**
 * Admin Routes
 * 
 * Admin-only operations for platform management
 */

import express from 'express';
import { authenticate } from '../middleware/auth';
import * as adminController from '../controllers/admin.controller';

const router = express.Router();

// All routes require authentication and admin role
// Role check is done in controllers

// Platform Fees
router.get('/fees', authenticate, adminController.getPlatformFees);
router.post('/fees/withdraw', authenticate, adminController.withdrawPlatformFees);

// Reconciliation
router.post('/reconciliation/run', authenticate, adminController.runReconciliation);
router.get('/reconciliation/reports', authenticate, adminController.getReconciliationReports);

// Withdrawal Batches
router.get('/withdrawals/batches', authenticate, adminController.getWithdrawalBatches);
router.post('/withdrawals/process-batch', authenticate, adminController.processBatch);

// User Management
router.get('/users/:userId/balance', authenticate, adminController.getUserBalance);
router.get('/users/:userId/bookings', authenticate, adminController.getUserBookings);
router.post('/users/:userId/credit', authenticate, adminController.issueCredit);

// Audit Logs
router.get('/audit-logs', authenticate, adminController.getAuditLogs);

// Treasury Stats
router.get('/treasury', authenticate, adminController.getTreasuryStats);

// Platform Stats (total users, bookings, etc.)
router.get('/stats', authenticate, adminController.getPlatformStats);

// Services Management (for campus managers and admins)
router.get('/services', authenticate, adminController.getServices);
router.post('/services', authenticate, adminController.createService);
router.put('/services/:id', authenticate, adminController.updateService);
router.delete('/services/:id', authenticate, adminController.deleteService);

// Campus Management (admin only)
router.get('/campuses', authenticate, adminController.getAllCampuses);
router.get('/campuses/aggregate/performance', authenticate, adminController.getAggregatePerformance);
router.get('/campuses/aggregate/metrics', authenticate, adminController.getAggregateMetrics);
router.get('/campuses/:campusId/performance', authenticate, adminController.getCampusPerformance);
router.get('/campuses/:campusId/metrics', authenticate, adminController.getCampusMetrics);
router.get('/campuses/:campusId/barbers', authenticate, adminController.getCampusBarbers);
router.post('/campuses/:campusId/manager', authenticate, adminController.assignCampusManager);

// Barber Management (admin only)
router.get('/barbers', authenticate, adminController.getAllBarbers);
router.get('/barbers/:barberRecordId/bookings', authenticate, adminController.getBarberBookings);
router.get('/bookings/:bookingId/messages', authenticate, adminController.getBookingMessages);

// User Management (admin only)
router.get('/users', authenticate, adminController.getAllUsers);

export default router;

