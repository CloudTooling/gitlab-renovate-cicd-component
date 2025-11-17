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

## Setup

If your Gitlab license allows creation of service accounts you can run the manual job `Setup Renovate`.
Just add the desired group id where the service account should be created via `variables`:
```
    SERVICEACCOUNT_GROUP_ID: ...
```

By default the `$CI_JOB_TOKEN` is used. To adjust assign to variable `$GITLAB_TOKEN`:

```
Setup Renovate:
  variables:
  SERVICEACCOUNT_GROUP_ID: ...
    GITLAB_TOKEN: $CI_JOB_TOKEN
```

Then run the manual job:

![](doc/docs/images/renovate-service-account-setup.png)

Then check the job output. It should look like this:
```
Login to GitLab CLI (gitlab.com)...
WARNING: One of GITLAB_TOKEN, GITLAB_ACCESS_TOKEN, OAUTH_TOKEN environment variables is set. If you don't want to use it for glab, unset it.
Creating service account gitlab_renovate_bot in group 117849439 ...
Created service account with id 31667576
Setting CI/CD variable in project
Created variable RENOVATE_TOKEN for cloudtooling/renovate with scope *.
```

On default it adds a CI/CD variable `RENOVATE_TOKEN` in the current Gitlab Job which is used by the CI/CD component. You can use this Account to add project to renovate.