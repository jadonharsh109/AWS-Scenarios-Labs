# Policy documents live in ../../policies so the console walkthrough and Terraform share one source.
# Minified on the way in: SCPs are limited to 5,120 characters, and whitespace counts.
resource "aws_organizations_policy" "this" {
  for_each = var.policies

  name        = each.key
  type        = each.value.type
  description = each.value.description
  content     = jsonencode(jsondecode(file("${path.module}/${var.policies_dir}/${each.value.file}")))
}

locals {
  policy_attachments = merge([
    for name, p in var.policies : {
      for target in p.targets : "${name}/${target}" => {
        policy = name
        target = target
      }
    }
  ]...)
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.policy_attachments

  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = local.target_ids[each.value.target]
}
