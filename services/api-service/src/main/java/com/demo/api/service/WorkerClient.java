package com.demo.api.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

@Service
public class WorkerClient {

    private static final Logger log = LoggerFactory.getLogger(WorkerClient.class);

    private final RestTemplate restTemplate;
    private final String workerServiceUrl;

    public WorkerClient(RestTemplate restTemplate,
                        @Value("${worker.service.url}") String workerServiceUrl) {
        this.restTemplate = restTemplate;
        this.workerServiceUrl = workerServiceUrl;
    }

    public String process() {
        log.info("Calling worker service at {}", workerServiceUrl);
        return restTemplate.getForObject(workerServiceUrl + "/process", String.class);
    }

    public String processSlow() {
        log.info("Calling worker service slow endpoint");
        return restTemplate.getForObject(workerServiceUrl + "/process-slow", String.class);
    }

    public String processError() {
        log.info("Calling worker service error endpoint");
        return restTemplate.getForObject(workerServiceUrl + "/process-error", String.class);
    }
}
