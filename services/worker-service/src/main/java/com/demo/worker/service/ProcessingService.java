package com.demo.worker.service;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Timer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.Random;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class ProcessingService {

    private static final Logger log = LoggerFactory.getLogger(ProcessingService.class);
    private static final Random random = new Random();

    private final Counter workerJobsProcessed;
    private final Timer workerJobDuration;
    private final AtomicInteger queueSize;

    public ProcessingService(Counter workerJobsProcessed,
                             Timer workerJobDuration,
                             AtomicInteger queueSizeGauge) {
        this.workerJobsProcessed = workerJobsProcessed;
        this.workerJobDuration = workerJobDuration;
        this.queueSize = queueSizeGauge;
    }

    public String processJob() {
        queueSize.incrementAndGet();
        try {
            return workerJobDuration.record(() -> {
                log.info("Starting job processing");

                // Simulate work
                int processingTime = 100 + random.nextInt(400);
                sleep(processingTime);

                log.info("Job processing completed in {}ms", processingTime);
                workerJobsProcessed.increment();

                return "processed_in_" + processingTime + "ms";
            });
        } finally {
            queueSize.decrementAndGet();
        }
    }

    public String processSlowJob() {
        queueSize.incrementAndGet();
        try {
            return workerJobDuration.record(() -> {
                log.info("Starting slow job processing");

                // Simulate heavy work
                int processingTime = 3000 + random.nextInt(5000);
                sleep(processingTime);

                log.info("Slow job completed in {}ms", processingTime);
                workerJobsProcessed.increment();

                return "slow_processed_in_" + processingTime + "ms";
            });
        } finally {
            queueSize.decrementAndGet();
        }
    }

    public String processWithPossibleError() {
        queueSize.incrementAndGet();
        try {
            log.info("Starting job with possible error");

            // 30% chance of failure
            if (random.nextInt(100) < 30) {
                log.error("Job failed due to simulated error");
                throw new RuntimeException("Simulated worker error");
            }

            int processingTime = 100 + random.nextInt(200);
            sleep(processingTime);

            log.info("Job completed successfully");
            workerJobsProcessed.increment();

            return "success_in_" + processingTime + "ms";
        } finally {
            queueSize.decrementAndGet();
        }
    }

    private void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
