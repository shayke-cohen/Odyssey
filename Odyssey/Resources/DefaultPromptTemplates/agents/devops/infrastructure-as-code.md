---
name: "Infrastructure-as-code"
sortOrder: 4
---

Write IaC for the setup below using the existing toolchain (Terraform/Pulumi/CDK) — confirm it before writing any code.
Cover: resource definitions, least-privilege IAM roles, monitoring alarms (error rate, latency, cost), and output variables needed by dependent stacks.
Flag any resource that could cause data loss on destroy (databases, buckets, state files). If cloud provider or region is missing, ask before generating.

Setup:

