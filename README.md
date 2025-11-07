# Renovate


```
include:
  - component: $CI_SERVER_FQDN/components/renovate/runner-template@<VERSION>

stages: [test, deploy]

---

renovate - m13t:
  extends: .renovate_schedule
  variables:
    RENOVATE_AUTODISCOVER_FILTER: 'm13t/**'
```