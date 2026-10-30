package com.badminton.v2.controller;

import com.badminton.v2.entity.*;
import com.badminton.v2.repository.*;
import com.badminton.v2.service.NotificationService;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

@RestController
@RequestMapping("/api/matches")
public class MatchmakingController {

    private final MatchPostRepository matchPostRepository;
    private final MatchParticipantRepository matchParticipantRepository;
    private final VenueRepository venueRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public MatchmakingController(MatchPostRepository matchPostRepository,
                                 MatchParticipantRepository matchParticipantRepository,
                                 VenueRepository venueRepository,
                                 UserRepository userRepository,
                                 NotificationService notificationService) {
        this.matchPostRepository = matchPostRepository;
        this.matchParticipantRepository = matchParticipantRepository;
        this.venueRepository = venueRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
    }

    @GetMapping
    public List<Map<String, Object>> listMatches(@RequestParam(required = false) String skill) {
        List<MatchPost> posts = matchPostRepository.findAllByOrderByIdDesc();
        List<Map<String, Object>> result = new ArrayList<>();
        for (MatchPost p : posts) {
            if (skill != null && !skill.isBlank() && !"ALL".equalsIgnoreCase(skill)) {
                if (!p.getRequiredSkill().equalsIgnoreCase(skill) && !"ALL".equalsIgnoreCase(p.getRequiredSkill())) {
                    continue;
                }
            }
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("post", p);
            item.put("participants", matchParticipantRepository.findByMatchIdOrderByIdAsc(p.getId()));
            result.add(item);
        }
        return result;
    }

    @PostMapping
    @Transactional
    public ResponseEntity<?> createMatchPost(@RequestBody Map<String, Object> body) {
        Long hostId = Long.parseLong(String.valueOf(body.getOrDefault("hostId", 1)));
        Long venueId = Long.parseLong(String.valueOf(body.getOrDefault("venueId", 1)));
        Long bookingId = body.get("bookingId") != null ? Long.parseLong(String.valueOf(body.get("bookingId"))) : null;

        User host = userRepository.findById(hostId).orElseThrow();
        Venue venue = venueRepository.findById(venueId).orElseThrow();

        MatchPost post = new MatchPost();
        post.setHostId(hostId);
        post.setHostName(host.getFullName());
        post.setHostSkill(host.getSkillLevel());
        post.setBookingId(bookingId);
        post.setVenueId(venueId);
        post.setVenueName(venue.getName());
        post.setVenueAddress(venue.getAddress());
        post.setCourtName(String.valueOf(body.getOrDefault("courtName", "Sân 2")));
        post.setTitle(String.valueOf(body.getOrDefault("title", "Giao lưu cầu lông vui vẻ - Tuyển thêm đồng đội")));
        post.setPlayDate(String.valueOf(body.getOrDefault("playDate", LocalDate.now().toString())));
        post.setStartTime(String.valueOf(body.getOrDefault("startTime", "18:00")));
        post.setEndTime(String.valueOf(body.getOrDefault("endTime", "20:00")));
        post.setRequiredSkill(String.valueOf(body.getOrDefault("requiredSkill", "TB_YEU")));
        post.setMaxPlayers(Integer.parseInt(String.valueOf(body.getOrDefault("maxPlayers", 6))));
        post.setCurrentPlayers(Integer.parseInt(String.valueOf(body.getOrDefault("currentPlayers", 3))));
        post.setFeePerPlayer(Double.parseDouble(String.valueOf(body.getOrDefault("feePerPlayer", 65000))));
        post.setStatus("OPEN");
        post.setCreatedAt(LocalDateTime.now().format(FMT));

        post = matchPostRepository.save(post);
        return ResponseEntity.ok(post);
    }

    @PostMapping("/{matchId}/join")
    @Transactional
    public ResponseEntity<?> requestJoinMatch(@PathVariable Long matchId, @RequestBody Map<String, Object> body) {
        Long userId = Long.parseLong(String.valueOf(body.get("userId")));
        MatchPost post = matchPostRepository.findById(matchId).orElseThrow();
        User user = userRepository.findById(userId).orElseThrow();

        if (matchParticipantRepository.findByMatchIdAndUserId(matchId, userId).isPresent()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Bạn đã gửi yêu cầu tham gia kèo này rồi!"));
        }
        if (post.getCurrentPlayers() >= post.getMaxPlayers()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo giao lưu này đã đủ người!"));
        }

        MatchParticipant mp = new MatchParticipant();
        mp.setMatchId(matchId);
        mp.setUserId(userId);
        mp.setUserName(user.getFullName());
        mp.setUserSkill(user.getSkillLevel());
        mp.setUserPhone(user.getPhone());
        mp.setStatus("PENDING");
        mp.setJoinedAt(LocalDateTime.now().format(FMT));
        mp = matchParticipantRepository.save(mp);

        notificationService.notifyUser(
                post.getHostId(),
                "Có người xin tham gia Kèo giao lưu!",
                user.getFullName() + " (Trình độ: " + user.getSkillLevel() + ") vừa xin vào kèo '" + post.getTitle() + "'.",
                "MATCHMAKING",
                "S15",
                post.getId()
        );
        return ResponseEntity.ok(mp);
    }

    @PatchMapping("/{matchId}/participants/{participantId}")
    @Transactional
    public ResponseEntity<?> reviewParticipant(@PathVariable Long matchId,
                                               @PathVariable Long participantId,
                                               @RequestBody Map<String, String> body) {
        String decision = body.getOrDefault("status", "APPROVED").toUpperCase();
        MatchPost post = matchPostRepository.findById(matchId).orElseThrow();
        MatchParticipant mp = matchParticipantRepository.findById(participantId).orElseThrow();

        mp.setStatus(decision);
        matchParticipantRepository.save(mp);

        if ("APPROVED".equals(decision)) {
            post.setCurrentPlayers(Math.min(post.getMaxPlayers(), post.getCurrentPlayers() + 1));
            if (post.getCurrentPlayers() >= post.getMaxPlayers()) {
                post.setStatus("FULL");
            }
            matchPostRepository.save(post);

            notificationService.notifyUser(
                    mp.getUserId(),
                    "Chủ kèo đã duyệt bạn vào đội!",
                    "Bạn đã được duyệt tham gia kèo '" + post.getTitle() + "' tại " + post.getVenueName() + " (" + post.getStartTime() + "-" + post.getEndTime() + ").",
                    "MATCHMAKING",
                    "S15",
                    post.getId()
            );
        } else {
            notificationService.notifyUser(
                    mp.getUserId(),
                    "Yêu cầu ghép kèo chưa phù hợp",
                    "Chủ kèo '" + post.getTitle() + "' đã từ chối yêu cầu tham gia.",
                    "MATCHMAKING",
                    "S15",
                    post.getId()
            );
        }
        return ResponseEntity.ok(Map.of("post", post, "participant", mp));
    }
}
