/*
 * Variables
 */

/*
 * Resources
 */
resource "aws_iam_instance_profile" "ecs_profile" {
  name = "ecs-instance-profile"
  role = "${aws_iam_role.ecs_instance_role.name}"
}

resource "aws_iam_role" "ecs_instance_role" {
  name               = "ecs-instance-role"
  assume_role_policy = "${file("${path.module}/policies/ecs_role.json")}"
}

resource "aws_iam_role_policy" "ecs_role" {
  name   = "ecs_role_policy"
  policy = "${file("${path.module}/policies/ecs_role_policy.json")}"
  role   = "${aws_iam_role.ecs_instance_role.id}"
}

resource "aws_iam_role_policy" "ecs_scheduler_role" {
  name   = "ecs-scheduler-role"
  policy = "${file("${path.module}/policies/ecs_scheduler_role_policy.json")}"
  role   = "${aws_iam_role.ecs_instance_role.id}"
}

resource "aws_iam_role_policy" "ecs_cloudwatch_logs" {
  name   = "ecs-cloudwatch-logs"
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
