package com.demo.api.config;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.atomic.AtomicInteger;

@Configuration
public class MetricsConfig {

    private final AtomicInteger activeRequests = new AtomicInteger(0);

    @Bean
    public AtomicInteger activeRequestsGauge() {
        return activeRequests;
    }

    @Bean
    public Counter apiRequestsTotal(MeterRegistry registry) {
        return Counter.builder("api_requests_total")
                .description("Total API requests")
                .tag("service", "api-service")
                .register(registry);
    }

    @Bean
    public Timer apiRequestDuration(MeterRegistry registry) {
        return Timer.builder("api_request_duration_seconds")
                .description("API request duration")
                .tag("service", "api-service")
                .publishPercentileHistogram()
                .register(registry);
    }

    @Bean
    public Gauge activeRequestsMetric(MeterRegistry registry) {
        return Gauge.builder("api_active_requests", activeRequests, AtomicInteger::get)
                .description("Currently active requests")
                .tag("service", "api-service")
                .register(registry);
    }
}
