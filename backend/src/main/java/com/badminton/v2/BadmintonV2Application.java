package com.badminton.v2;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class BadmintonV2Application {
    public static void main(String[] args) {
        SpringApplication.run(BadmintonV2Application.class, args);
    }
}
