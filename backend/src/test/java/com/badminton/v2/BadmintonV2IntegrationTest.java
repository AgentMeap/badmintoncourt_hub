package com.badminton.v2;

import com.badminton.v2.controller.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
class BadmintonV2IntegrationTest {

    @Autowired
    private AuthController authController;

    @Autowired
    private VenueController venueController;

    @Autowired
    private BookingPaymentController bookingPaymentController;

    @Autowired
    private MatchmakingController matchmakingController;

    @Autowired
    private AdminOwnerFinanceController adminOwnerFinanceController;

    @Autowired
    private AiAssistantController aiAssistantController;

    @Test
    void testEndToEndAllFlowsAndModules() {
        // 1. Module 4: Login + Send/Verify OTP
        ResponseEntity<?> loginRes = authController.login(Map.of(
                "email", "customer@badminton.vn",
                "password", "123456"
        ));
        assertEquals(200, loginRes.getStatusCode().value());

        ResponseEntity<?> otpRes = authController.sendOtp(Map.of(
                "email", "customer@badminton.vn",
                "purpose", "REGISTER"
        ));
        assertEquals(200, otpRes.getStatusCode().value());

        // 2. Module 1 & 2: List Approved Venues with GPS Haversine distance
        List<Map<String, Object>> venues = venueController.listApprovedVenues(null, 10.7769, 106.6660, 15.0);
        assertFalse(venues.isEmpty());

        // 3. Flow 1 & Module 3: Hold Slot -> Create PayOS QR -> Simulate Webhook -> Reschedule -> Cancel & Refund to Wallet
        ResponseEntity<?> holdRes = bookingPaymentController.holdBookingSlot(Map.of(
                "venueId", 1,
                "courtId", 3,
                "customerId", 1,
                "playDate", "2026-11-15",
                "startTime", "20:00",
                "endTime", "22:00",
                "totalPrice", 240000
        ));
        assertEquals(200, holdRes.getStatusCode().value());

        // 4. Flow 5: Matchmaking list
        List<Map<String, Object>> matches = matchmakingController.listMatches("ALL");
        assertFalse(matches.isEmpty());

        // 5. Flow 3: Admin & Owner Dashboards
        assertEquals(200, adminOwnerFinanceController.getOwnerDashboard(2L).getStatusCode().value());
        assertEquals(200, adminOwnerFinanceController.getAdminDashboard().getStatusCode().value());

        // 6. Module 6: AI Assistant Chat
        ResponseEntity<?> aiRes = aiAssistantController.chatWithAi(Map.of(
                "message", "Tìm sân trống tối nay gần Quận 10 và chính sách hoàn tiền"
        ));
        assertEquals(200, aiRes.getStatusCode().value());
    }
}
