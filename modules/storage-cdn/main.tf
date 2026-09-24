###############################################################################
# S3 bucket names must be unique across ALL of AWS, not just your account, so
# something unique has to be in the name. An account id would do it but leaks
# the account number into every bucket ARN, log line and error message, so a
# short random token is generated instead and kept in state forever.
###############################################################################
resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true

  # Never regenerate: a new value would mean new buckets and lost objects.
  lifecycle {
    ignore_changes = all
  }
}

locals {
  suffix           = var.bucket_suffix != "" ? var.bucket_suffix : random_string.bucket_suffix.result
  app_bucket_name  = "${var.name_prefix}-app-${local.suffix}"
  data_bucket_name = "${var.name_prefix}-data-${local.suffix}"
}

###############################################################################
# S3: web SPA bucket (CloudFront origin) and user-media bucket
###############################################################################
resource "aws_s3_bucket" "app" {
  bucket = local.app_bucket_name
  tags = merge(var.tags, {
    Name               = local.app_bucket_name
    Component          = "edge"
    Service            = "s3"
    Purpose            = "web-spa"
    DataClassification = "public"
  })
}

resource "aws_s3_bucket" "data" {
  bucket = local.data_bucket_name
  tags = merge(var.tags, {
    Name               = local.data_bucket_name
    Component          = "edge"
    Service            = "s3"
    Purpose            = "user-media"
    DataClassification = "confidential"
    Backup             = "required"
  })
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "app" {
  bucket = aws_s3_bucket.app.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_ownership_controls" "data" {
  bucket = aws_s3_bucket.data.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

# Clean up old versions so storage cost doesn't grow forever
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration { noncurrent_days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

###############################################################################
# CloudFront logging bucket (dev has Standard logging On, Cookie logging Off)
###############################################################################
resource "aws_s3_bucket" "logs" {
  count  = var.enable_standard_logging ? 1 : 0
  bucket = "${var.name_prefix}-cdn-logs-${local.suffix}"

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-cdn-logs-${local.suffix}"
    Component = "edge"
    Purpose   = "cloudfront-access-logs"
  })
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count  = var.enable_standard_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  # CloudFront standard logging writes with an ACL, so BucketOwnerEnforced
  # cannot be used here - this is the one bucket that needs ACLs enabled.
  rule { object_ownership = "BucketOwnerPreferred" }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count                   = var.enable_standard_logging ? 1 : 0
  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.enable_standard_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration { days = var.log_retention_days }
  }
}

###############################################################################
# CloudFront: Origin Access Control + distribution
###############################################################################
resource "aws_cloudfront_origin_access_control" "app" {
  name                              = "${var.name_prefix}-app-oac"
  description                       = "OAC for ${local.app_bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS managed policies, matching the dev distribution exactly
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

locals {
  s3_origin_id    = "s3-${local.app_bucket_name}"
  admin_origin_id = "${var.name_prefix}-admin-api-nlb"

  # The admin behaviours only exist once the admin NLB does.
  admin_enabled = var.admin_nlb_dns_name != ""

  # A custom domain requires a real, ISSUED certificate. Until one is supplied
  # CloudFront keeps its default certificate and no alias is attached.
  use_custom_cert = var.certificate_arn != ""
}

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix}-app"
  default_root_object = "index.html"
  price_class         = var.price_class
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].arn : null
  aliases             = local.use_custom_cert ? var.aliases : []

  # HTTP/2, HTTP/1.1, HTTP/1.0 - matching dev
  http_version = "http2"

  # ---- origin 1: the SPA bucket, via OAC ----
  origin {
    domain_name              = aws_s3_bucket.app.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.app.id
  }

  # ---- origin 2: the admin API NLB, HTTP-only to origin ----
  dynamic "origin" {
    for_each = local.admin_enabled ? [1] : []
    content {
      domain_name = var.admin_nlb_dns_name
      origin_id   = local.admin_origin_id

      custom_origin_config {
        http_port                = 80
        https_port               = 443
        origin_protocol_policy   = "http-only"
        origin_ssl_protocols     = ["TLSv1.2"]
        origin_read_timeout      = 30
        origin_keepalive_timeout = 5
      }
    }
  }

  # ---- precedence 0: /v1/admin/* -> admin NLB ----
  dynamic "ordered_cache_behavior" {
    for_each = local.admin_enabled ? [1] : []
    content {
      path_pattern             = "/v1/admin/*"
      target_origin_id         = local.admin_origin_id
      viewer_protocol_policy   = "https-only"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      compress                 = true
      cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
    }
  }

  # ---- precedence 1: /admin -> S3 ----
  dynamic "ordered_cache_behavior" {
    for_each = local.admin_enabled ? [1] : []
    content {
      path_pattern           = "/admin"
      target_origin_id       = local.s3_origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true
      cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    }
  }

  # ---- precedence 2: /admin/* -> S3 ----
  dynamic "ordered_cache_behavior" {
    for_each = local.admin_enabled ? [1] : []
    content {
      path_pattern           = "/admin/*"
      target_origin_id       = local.s3_origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true
      cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    }
  }

  # ---- precedence 3 (default): * -> S3 ----
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # SPA fallback. dev has exactly one custom error response: 403 -> /index.html
  # with a 200 and a 10 second minimum TTL.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  dynamic "logging_config" {
    for_each = var.enable_standard_logging ? [1] : []
    content {
      bucket          = aws_s3_bucket.logs[0].bucket_domain_name
      prefix          = "cloudfront/"
      include_cookies = false # dev: Cookie logging Off
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  # Without an ISSUED certificate CloudFront must use its own; minimum_protocol
  # _version is only meaningful on a custom certificate.
  dynamic "viewer_certificate" {
    for_each = local.use_custom_cert ? [1] : []
    content {
      acm_certificate_arn      = var.certificate_arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.use_custom_cert ? [] : [1]
    content {
      cloudfront_default_certificate = true
    }
  }

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-app"
    Component = "edge"
    Service   = "cloudfront"
  })

  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

###############################################################################
# WAF (CLOUDFRONT scope - must be created in us-east-1)
###############################################################################
resource "aws_wafv2_web_acl" "cloudfront" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.name_prefix}-cloudfront-waf"
  description = "Web ACL attached to the ${var.name_prefix} CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIp"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cloudfront-waf" })
}
