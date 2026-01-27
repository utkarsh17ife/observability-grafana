package com.demo.worker.config;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.atomic.AtomicInteger;

@Configuration
public class MetricsConfig {

    private final AtomicInteger queueSize = new AtomicInteger(0);

    @Bean
    public AtomicInteger queueSizeGauge() {
        return queueSize;
    }

    @Bean
    public Counter workerJobsProcessed(MeterRegistry registry) {
        return Counter.builder("worker_jobs_processed_total")
                .description("Total jobs processed by worker")
                .tag("service", "worker-service")
                .register(registry);
    }

    @Bean
    public Timer workerJobDuration(MeterRegistry registry) {
        return Timer.builder("worker_job_duration_seconds")
                .description("Worker job processing duration")
                .tag("service", "worker-service")
                .publishPercentileHistogram()
                .register(registry);
    }

    @Bean
    public Gauge workerQueueSize(MeterRegistry registry) {
        return Gauge.builder("worker_queue_size", queueSize, AtomicInteger::get)
                .description("Current queue size")
                .tag("service", "worker-service")
                .register(registry);
    }
}
