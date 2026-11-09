package com.badminton.v2.controller;

import com.badminton.v2.entity.Review;
import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.ReviewRepository;
import com.badminton.v2.repository.VenueRepository;
import com.badminton.v2.service.NotificationService;
import com.badminton.v2.security.CurrentUser;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

@RestController
@RequestMapping("/api/reviews")
public class ReviewController {

    private final ReviewRepository reviewRepository;
    private final VenueRepository venueRepository;
    private final NotificationService notificationService;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public ReviewController(ReviewRepository reviewRepository,
                            VenueRepository venueRepository,
                            NotificationService notificationService) {
        this.reviewRepository = reviewRepository;
        this.venueRepository = venueRepository;
        this.notificationService = notificationService;
    }

    @GetMapping
    public List<Review> getAllReviews() {
        return reviewRepository.findAll(org.springframework.data.domain.Sort.by(org.springframework.data.domain.Sort.Direction.DESC, "id"));
    }

    @GetMapping("/venue/{venueId}")
    public List<Review> getReviewsForVenue(@PathVariable Long venueId) {
        return reviewRepository.findByVenueIdOrderByIdDesc(venueId);
    }

    @PostMapping
    @Transactional
    public ResponseEntity<?> submitReview(@RequestBody Map<String, Object> body) {
        String bookingCode = String.valueOf(body.getOrDefault("bookingCode", "BK-000000"));
        Long venueId = Long.parseLong(String.valueOf(body.get("venueId")));
        String venueName = String.valueOf(body.getOrDefault("venueName", "Sân Cầu Lông"));
        Long userId = CurrentUser.idOr(body.getOrDefault("userId", 1));
        String userName = String.valueOf(body.getOrDefault("userName", "Người chơi"));
        int rating = Integer.parseInt(String.valueOf(body.getOrDefault("rating", 5)));
        String comment = String.valueOf(body.getOrDefault("comment", ""));
        if (rating < 1 || rating > 5) {
            return ResponseEntity.badRequest().body(Map.of("error", "Số sao phải từ 1 đến 5."));
        }

        String tagsStr = "";
        Object tagsObj = body.get("tags");
        if (tagsObj instanceof List<?> list) {
            tagsStr = String.join(", ", list.stream().map(String::valueOf).toList());
        } else if (tagsObj != null) {
            tagsStr = String.valueOf(tagsObj);
        }

        Review review = new Review(
                bookingCode,
                venueId,
                venueName,
                userId,
                userName,
                rating,
                tagsStr,
                comment,
                LocalDateTime.now().format(FMT)
        );
        review = reviewRepository.save(review);

        // Recalculate Venue Average Rating
        Optional<Venue> vOpt = venueRepository.findById(venueId);
        if (vOpt.isPresent()) {
            Venue v = vOpt.get();
            List<Review> allReviews = reviewRepository.findByVenueIdOrderByIdDesc(venueId);
            double avgRating = allReviews.stream().mapToInt(Review::getRating).average().orElse(rating);
            v.setRating(Math.round(avgRating * 10.0) / 10.0);
            venueRepository.save(v);

            notificationService.notifyUser(
                    v.getOwnerId(),
                    "Cơ sở nhận được đánh giá mới (" + rating + "★)",
                    userName + " vừa đánh giá " + rating + " sao cho cơ sở '" + v.getName() + "': \"" + (comment.isBlank() ? "Đánh giá tốt" : comment) + "\"",
                    "BOOKING",
                    "S19",
                    v.getId()
            );
        }

        return ResponseEntity.ok(review);
    }
}
