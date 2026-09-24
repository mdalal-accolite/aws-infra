# The manual step between the two Terraform passes

## Why Terraform runs twice

Look at the dev inventory's load balancing section:

> NLB `k8s-scribl-scriblap-fc2081e221` — internet-facing, **k8s-provisioned**

The `k8s-` prefix is the tell. Kubernetes created that load balancer, not Terraform. When you
apply a `Service` of type `LoadBalancer`, the controller inside EKS calls the AWS API and creates
an NLB, a target group, and two security groups. Terraform has no idea they exist.

API Gateway's VPC Link needs that NLB's ARN. So:

```
Pass 1 (Phase 4)         →  everything except API Gateway
kubectl apply (Phase 6)  →  Kubernetes creates the internal NLB
Pass 2 (Phase 6.4)       →  API Gateway + VPC Link, pointed at that NLB
```

That is what `enable_api_gateway` and `nlb_arn` in `live/<env>/main.tf` are for.

**Why not have Terraform create the NLB?** Because then two systems own it. Kubernetes would
keep trying to create its own, Terraform would keep reverting whatever Kubernetes changed, and
every `kubectl apply` would produce Terraform drift. Letting Kubernetes own its own load
balancer and telling Terraform about it afterwards is the boring, stable arrangement.

## Your Service must be internal

The dev NLB is internet-facing. On private subnets it must be internal, or the controller will
fail to place it (there is nothing to attach a public NLB to) and you would be re-opening the
hole this whole exercise closed.

`deploy/k8s/api/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: scribl-api
  namespace: scribl
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    # internal, not internet-facing — this is the important line
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/health"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "3000"
spec:
  type: LoadBalancer
  selector:
    app: scribl-api
  ports:
    - name: http
      port: 80
      targetPort: 3000
      protocol: TCP
```

`deploy/k8s/api/serviceaccount.yaml` — the name must be exactly `scribl-api`, because that is
what Terraform's Pod Identity association is bound to. No annotation is needed; Pod Identity
works by association, unlike the older IRSA approach.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: scribl-api
  namespace: scribl
```

`deploy/k8s/api/deployment.yaml` (abbreviated):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: scribl-api
  namespace: scribl
spec:
  replicas: 2
  selector:
    matchLabels: { app: scribl-api }
  template:
    metadata:
      labels: { app: scribl-api }
    spec:
      serviceAccountName: scribl-api        # <-- gets the IAM role
      containers:
        - name: api
          image: <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com/scribl-mobile-app:stage-001
          ports:
            - containerPort: 3000
          env:
            - name: AWS_REGION
              value: us-east-1
            - name: REDIS_URL
              value: rediss://<REDIS_ENDPOINT>:6379   # rediss:// — TLS is now on
          readinessProbe:
            httpGet: { path: /health, port: 3000 }
          resources:
            requests: { cpu: "250m", memory: "512Mi" }
            limits:   { memory: "1Gi" }
```

Resource *requests* matter on Auto Mode: they are what the scheduler uses to decide what size
instance to launch. A pod with no requests may schedule oddly or not at all.

## Getting the NLB ARN

```bash
cd live/stage
VPC=$(terraform output -raw vpc_id)

aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC'].{Name:LoadBalancerName,Scheme:Scheme,Arn:LoadBalancerArn}" \
  --output table
```

Confirm `Scheme` is `internal`. If it says `internet-facing`, the annotation did not take —
fix the Service, delete it, re-apply, and wait for a new NLB.

Then check targets are healthy before wiring API Gateway to it:

```bash
TG=$(aws elbv2 describe-target-groups --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query 'TargetHealthDescriptions[].TargetHealth.State'
# => ["healthy","healthy"]
```

## Fresh Auto Mode clusters have zero nodes

```bash
kubectl get nodes
# No resources found
```

That is correct, not broken. Auto Mode provisions instances when a pod needs one. Apply a
Deployment and watch:

```bash
kubectl -n scribl get pods -w
kubectl get nodes -w          # a node appears within a minute or two
```

If a pod stays `Pending` for more than about three minutes:

```bash
kubectl -n scribl describe pod <POD_NAME> | tail -25
```

Usual causes: no resource requests set, a node selector that matches nothing, or an image the
node role cannot pull (it has `AmazonEC2ContainerRegistryPullOnly`, scoped to your account's
ECR — images from another account's registry will not pull).

## Teardown order

Kubernetes-created resources must go before Terraform-created ones, because Terraform cannot
delete a VPC that still has an NLB and its security groups in it, and it does not know how to
delete them.

```bash
kubectl delete -f deploy/k8s/api/
kubectl -n scribl get svc          # wait until no LoadBalancer remains
# only now:
terraform destroy
```

Skipping this is the number one cause of a `terraform destroy` that hangs for 20 minutes on
`aws_subnet` with a `DependencyViolation`.
