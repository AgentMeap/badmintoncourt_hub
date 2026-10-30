package com.badminton.v2.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

@Configuration
public class OpenApiConfig {

    private static final String BEARER_AUTH = "bearerAuth";

    @Bean
    public OpenAPI badmintonOpenApi() {
        return new OpenAPI()
                .info(new Info()
                        .title("Badminton V2 API")
                        .version("1.0.0")
                        .description("Badminton Court Management Platform Backend (Spring Boot + SQLite)"))
                .servers(List.of(new Server().url("/").description("Current server")))
                .components(new Components().addSecuritySchemes(BEARER_AUTH,
                        new SecurityScheme()
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")))
                .addSecurityItem(new SecurityRequirement().addList(BEARER_AUTH));
    }
}
