# December 5th Results

### Infra Deployed

- ROSA
- Authorino wip branch: `kubectl patch authorino authorino -n kuadrant-system --type='merge' -p '{"spec":{"image":"quay.io/bmajsak/authorino:k8s-client"}}'`

```
  | Users | Iterations | Total Requests | Success Rate | Avg Response Time | Req/Sec |
  |-------|------------|----------------|--------------|-------------------|---------|
  | 1     | 1          | 1              | 100%         | 306ms             | ~3      |
  | 5     | 20         | 100            | 100%         | 73ms              | ~61     |
  | 10    | 20         | 200            | 100%         | 244ms             | ~39     |
  | 15    | 20         | 300            | 100%         | 209ms             | ~59     |
  | 20    | 20         | 400            | 90%          | 158ms             | ~94     |
  | 22    | 22         | 484            | 86%          | 474ms             | ~41     |
  | 25    | 25         | 625            | 52%          | 180ms             | ~116    |
  | 30    | 30         | 900            | 10%          | 347ms             | ~80     |
  | 50    | 50         | 2500           | 40%          | 710ms             | ~67     |
  | 100   | 100        | 10000          | 1%           | 373ms             | ~206    |
```

**Breakpoint: ~20 concurrent users**

Replicate with these Commands:

```
  # Set host
  MAAS_HOST=<YOUR_HOST>

  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=1 BURST_ITERATIONS=1 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=5 BURST_ITERATIONS=20 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=10 BURST_ITERATIONS=20 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=15 BURST_ITERATIONS=20 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=20 BURST_ITERATIONS=20 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=22 BURST_ITERATIONS=22 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=25 BURST_ITERATIONS=25 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=30 BURST_ITERATIONS=30 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=50 BURST_ITERATIONS=50 k6 run k6/maas-performance-test.js
  HOST=$MAAS_HOST MODEL_NAME=facebook/opt-125m BURST_VUS=100 BURST_ITERATIONS=100 k6 run k6/maas-performance-test.js
```

