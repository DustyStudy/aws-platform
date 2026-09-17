# sample-service-onboarding

A worked example of what an app team's own repo looks like when it consumes
this platform's self-service onboarding path. Not a real service - just the
two files that matter, so the shape of the integration is copy-pasteable.

- [`onboard.yml`](onboard.yml) - calls the reusable
  [`onboard-service.yml`](../../.github/workflows/onboard-service.yml)
  workflow published by this repo.
- [`deploy.yml`](deploy.yml) - a follow-on deploy workflow, once onboarding
  has landed: builds an image, pushes it to the ECR repo the platform
  provisioned, and deploys into the namespace the platform provisioned,
  using the IRSA-annotated `ServiceAccount` the platform already created.

See [`docs/ONBOARDING.md`](../../docs/ONBOARDING.md) for the full walkthrough.
