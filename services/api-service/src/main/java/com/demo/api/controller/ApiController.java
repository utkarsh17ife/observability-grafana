package com.demo.api.controller;

import com.demo.api.service.WorkerClient;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Timer;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import io.opentelemetry.instrumentation.annotations.SpanAttribute;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.Random;
import java.util.concurrent.atomic.AtomicInteger;

@RestController
public class ApiController {

    private static final Logger log = LoggerFactory.getLogger(ApiController.class);
    private static final Random random = new Random();

    // Get tracer from OpenTelemetry - the Java agent provides the implementation
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("api-service", "1.0.0");

    private final WorkerClient workerClient;
    private final Counter apiRequestsTotal;
    private final Timer apiRequestDuration;
    private final AtomicInteger activeRequests;

    public ApiController(WorkerClient workerClient,
                         Counter apiRequestsTotal,
                         Timer apiRequestDuration,
                         AtomicInteger activeRequestsGauge) {
        this.workerClient = workerClient;
        this.apiRequestsTotal = apiRequestsTotal;
        this.apiRequestDuration = apiRequestDuration;
        this.activeRequests = activeRequestsGauge;
    }

    @GetMapping("/fast")
    public ResponseEntity<Map<String, Object>> fast() {
        activeRequests.incrementAndGet();
        try {
            return apiRequestDuration.record(() -> {
                apiRequestsTotal.increment();
                log.info("Processing fast request");
                sleep(30 + random.nextInt(50));
                log.info("Fast request completed");
                return ResponseEntity.ok(Map.of(
                        "status", "success",
                        "endpoint", "fast",
                        "latency_ms", 50
                ));
            });
        } finally {
            activeRequests.decrementAndGet();
        }
    }

    @GetMapping("/slow")
    public ResponseEntity<Map<String, Object>> slow() {
        activeRequests.incrementAndGet();
        try {
            return apiRequestDuration.record(() -> {
                apiRequestsTotal.increment();
                log.info("Processing slow request - this will take a while");
                int delay = 2000 + random.nextInt(3000);

                // === MANUAL SPAN CREATION ===
                // Create a child span for the slow processing work
                Span processingSpan = tracer.spanBuilder("slow-processing")
                        .setSpanKind(SpanKind.INTERNAL)
                        .setAttribute("processing.delay_ms", delay)        // Custom attribute
                        .setAttribute("processing.type", "simulated")      // Custom attribute
                        .startSpan();

                try (Scope scope = processingSpan.makeCurrent()) {
                    // Everything in this block is under the "slow-processing" span
                    log.info("Starting slow processing with delay: {}ms", delay);

                    // Simulate work in stages
                    simulateStageOne(delay / 2);
                    simulateStageTwo(delay / 2);

                    processingSpan.addEvent("processing-completed");  // Add event to span
                } catch (Exception e) {
                    processingSpan.setStatus(StatusCode.ERROR, e.getMessage());
                    processingSpan.recordException(e);
                    throw e;
                } finally {
                    processingSpan.end();  // IMPORTANT: Always end the span
                }

                log.info("Slow request completed after {}ms", delay);
                return ResponseEntity.ok(Map.of(
                        "status", "success",
                        "endpoint", "slow",
                        "latency_ms", delay
                ));
            });
        } finally {
            activeRequests.decrementAndGet();
        }
    }

    // === @WithSpan ANNOTATION APPROACH (simpler) ===
    // The annotation automatically creates a span named after the method
    @WithSpan("stage-one-processing")
    private void simulateStageOne(@SpanAttribute("stage.delay_ms") int delayMs) {
        log.info("Executing stage one");
        sleep(delayMs);
    }

    @WithSpan("stage-two-processing")
    private void simulateStageTwo(@SpanAttribute("stage.delay_ms") int delayMs) {
        log.info("Executing stage two");
        sleep(delayMs);
    }

    @GetMapping("/error")
    public ResponseEntity<Map<String, Object>> error() {
        activeRequests.incrementAndGet();

        // Get the current span (auto-created by the Java agent for this HTTP request)
        Span currentSpan = Span.current();

        try {
            apiRequestsTotal.increment();
            currentSpan.setAttribute("error.simulated", true);
            log.error("Simulating error condition");

            RuntimeException ex = new RuntimeException("Simulated error for observability demo");

            // Record the exception on the span - this makes it visible in Grafana/Tempo
            currentSpan.recordException(ex);
            currentSpan.setStatus(StatusCode.ERROR, "Simulated error");

            throw ex;
        } finally {
            activeRequests.decrementAndGet();
        }
    }

    @GetMapping("/external-call")
    public ResponseEntity<Map<String, Object>> externalCall() {
        activeRequests.incrementAndGet();
        String requestId = java.util.UUID.randomUUID().toString().substring(0, 8);

        // Add business context to MDC - these will appear in all logs within this request
        MDC.put("request_id", requestId);
        MDC.put("endpoint", "/external-call");
        MDC.put("operation", "worker-integration");

        try {
            return apiRequestDuration.record(() -> {
                apiRequestsTotal.increment();

                // Create a span for the external call preparation
                Span prepSpan = tracer.spanBuilder("prepare-worker-call")
                        .setAttribute("request.id", requestId)
                        .startSpan();

                try (Scope scope = prepSpan.makeCurrent()) {
                    log.info("Preparing external call to worker service [request_id={}]", requestId);
                    log.debug("Validating request parameters");
                    prepSpan.addEvent("validation-complete");
                } finally {
                    prepSpan.end();
                }

                // The actual call - will create its own span via HTTP client instrumentation
                log.info("Invoking worker service [request_id={}]", requestId);
                long startTime = System.currentTimeMillis();
                String result = workerClient.process();
                long duration = System.currentTimeMillis() - startTime;

                // Log with structured context
                log.info("Worker call completed [request_id={}, duration_ms={}, result={}]",
                        requestId, duration, result);

                return ResponseEntity.ok(Map.of(
                        "status", "success",
                        "endpoint", "external-call",
                        "request_id", requestId,
                        "worker_response", result,
                        "duration_ms", duration
                ));
            });
        } finally {
            // Clean up MDC
            MDC.remove("request_id");
            MDC.remove("endpoint");
            MDC.remove("operation");
            activeRequests.decrementAndGet();
        }
    }

    @GetMapping("/external-call-slow")
    public ResponseEntity<Map<String, Object>> externalCallSlow() {
        activeRequests.incrementAndGet();
        try {
            return apiRequestDuration.record(() -> {
                apiRequestsTotal.increment();
                log.info("Starting slow external call to worker service");
                String result = workerClient.processSlow();
                log.info("Slow external call completed");
                return ResponseEntity.ok(Map.of(
                        "status", "success",
                        "endpoint", "external-call-slow",
                        "worker_response", result
                ));
            });
        } finally {
            activeRequests.decrementAndGet();
        }
    }

    @PostMapping("/load")
    public ResponseEntity<Map<String, Object>> generateLoad(@RequestParam(defaultValue = "10") int count) {
        log.info("Generating {} requests for load testing", count);
        int fast = 0, slow = 0, errors = 0, external = 0;

        for (int i = 0; i < count; i++) {
            int type = random.nextInt(4);
            try {
                switch (type) {
                    case 0 -> { fast(); fast++; }
                    case 1 -> { slow(); slow++; }
                    case 2 -> { try { error(); } catch (Exception e) { errors++; } }
                    case 3 -> { externalCall(); external++; }
                }
            } catch (Exception e) {
                log.warn("Request failed during load generation: {}", e.getMessage());
            }
        }

        log.info("Load generation completed: fast={}, slow={}, errors={}, external={}", fast, slow, errors, external);
        return ResponseEntity.ok(Map.of(
                "status", "completed",
                "total", count,
                "fast", fast,
                "slow", slow,
                "errors", errors,
                "external", external
        ));
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }

    private void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
