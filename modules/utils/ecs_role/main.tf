/*
 * Variables
 */
variable "environment" {}

/*
 * Resources
 */
resource "aws_iam_instance_profile" "ecs_profile" {
  name = "ecs-instance-profile-${var.environment}"
  role = "${aws_iam_role.ecs_instance_role.name}"
}

resource "aws_iam_role" "ecs_instance_role" {
  name               = "ecs-instance-role-${var.environment}"
  assume_role_policy = "${file("${path.module}/policies/ecs_role.json")}"
}

resource "aws_iam_role_policy" "ecs_role" {
  name   = "ecs_role_policy_${var.environment}"
  policy = "${file("${path.module}/policies/ecs_role_policy.json")}"
  role   = "${aws_iam_role.ecs_instance_role.id}"
}

resource "aws_iam_role_policy" "ecs_scheduler_role" {
  name   = "ecs-scheduler-role-${var.environment}"
  policy = "${file("${path.module}/policies/ecs_scheduler_role_policy.json")}"
  role   = "${aws_iam_role.ecs_instance_role.id}"
}

resource "aws_iam_role_policy" "ecs_cloudwatch_logs" {
  name   = "ecs-cloudwatch-logs-${var.environment}"
  policy = "${file("${path.module}/policies/ecs_cloudwatch_logs.json")}"
  role   = "${aws_iam_role.ecs_instance_role.id}"
}

/*
 * Outputs
 */
output "instance_profile_id" {
  value = "${aws_iam_instance_profile.ecs_profile.id}"
}

output "instance_role_arn" {
  value = "${aws_iam_role.ecs_instance_role.arn}"
}
