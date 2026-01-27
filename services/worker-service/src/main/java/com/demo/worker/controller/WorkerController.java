package com.demo.worker.controller;

import com.demo.worker.service.ProcessingService;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class WorkerController {

    private static final Logger log = LoggerFactory.getLogger(WorkerController.class);
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("worker-service", "1.0.0");

    private final ProcessingService processingService;

    public WorkerController(ProcessingService processingService) {
        this.processingService = processingService;
    }

    @GetMapping("/process")
    public ResponseEntity<Map<String, Object>> process() {
        // Get the current span - this contains the trace context propagated from api-service
        Span currentSpan = Span.current();
        String traceId = currentSpan.getSpanContext().getTraceId();

        MDC.put("endpoint", "/process");
        try {
            log.info("Received process request from upstream service [trace_id={}]", traceId);

            // Create a child span for the actual processing
            Span processingSpan = tracer.spanBuilder("worker-job-execution")
                    .setSpanKind(SpanKind.INTERNAL)
                    .setAttribute("job.type", "standard")
                    .startSpan();

            String result;
            try (Scope scope = processingSpan.makeCurrent()) {
                log.info("Starting job execution");
                result = processingService.processJob();
                processingSpan.addEvent("job-completed");
                log.info("Job execution completed with result: {}", result);
            } finally {
                processingSpan.end();
            }

            log.info("Returning response to caller [trace_id={}]", traceId);
            return ResponseEntity.ok(Map.of(
                    "status", "success",
                    "result", result,
                    "trace_id", traceId
            ));
        } finally {
            MDC.remove("endpoint");
        }
    }

    @GetMapping("/process-slow")
    public ResponseEntity<Map<String, Object>> processSlow() {
        Span currentSpan = Span.current();
        String traceId = currentSpan.getSpanContext().getTraceId();

        MDC.put("endpoint", "/process-slow");
        try {
            log.info("Received slow process request [trace_id={}]", traceId);
            log.warn("This request will take a while to complete");

            long startTime = System.currentTimeMillis();
            String result = processingService.processSlowJob();
            long duration = System.currentTimeMillis() - startTime;

            log.info("Slow job completed [duration_ms={}, result={}]", duration, result);
            return ResponseEntity.ok(Map.of(
                    "status", "success",
                    "result", result,
                    "duration_ms", duration
            ));
        } finally {
            MDC.remove("endpoint");
        }
    }

    @GetMapping("/process-error")
    public ResponseEntity<Map<String, Object>> processError() {
        Span currentSpan = Span.current();
        String traceId = currentSpan.getSpanContext().getTraceId();

        MDC.put("endpoint", "/process-error");
        try {
            log.info("Received process request with possible error [trace_id={}]", traceId);
            log.debug("Attempting potentially failing operation");

            String result = processingService.processWithPossibleError();

            log.info("Process completed successfully (no error this time)");
            return ResponseEntity.ok(Map.of(
                    "status", "success",
                    "result", result
            ));
        } catch (Exception e) {
            log.error("Process failed with error: {}", e.getMessage(), e);
            throw e;
        } finally {
            MDC.remove("endpoint");
        }
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }
}
