provider "aws" {
  region = "us-east-1"  # Change to your preferred region
}

# Reference existing IAM Role for Lambda
data "aws_iam_role" "lambda_role" {
  name = "lambda_exec_role"
}

# IAM Policy for Logging
resource "aws_iam_policy_attachment" "lambda_logs" {
  name       = "lambda_logs"
  roles      = [data.aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

locals {
  apis = {
    "grupo2_lambda_1" = "lambda_hello_1.zip"
    "grupo2_lambda_2" = "lambda_hello_2.zip"
    "grupo2_lambda_3" = "lambda_hello_3.zip"
  }
}

resource "aws_lambda_function" "hello_lambda" {
  for_each      = local.apis
  function_name = each.key
  role          = data.aws_iam_role.lambda_role.arn
  runtime       = "python3.9"
  handler       = "lambda_hello.lambda_handler"
  filename      = "${path.module}/${each.value}"
  source_code_hash = filebase64sha256("${path.module}/${each.value}")

  environment {
    variables = {
      API_NAME = each.key
    }
  }
}

# API Gateway for Each Lambda Function
resource "aws_api_gateway_rest_api" "api" {
  for_each = aws_lambda_function.hello_lambda
  name     = "${each.key}_api"
}
resource "aws_api_gateway_method" "root" {
  for_each      = aws_api_gateway_rest_api.api
  rest_api_id   = each.value.id
  resource_id   = each.value.root_resource_id  # Use the root resource directly
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  for_each    = aws_api_gateway_rest_api.api
  rest_api_id = each.value.id
  resource_id = each.value.root_resource_id    # Use the root resource directly
  http_method = aws_api_gateway_method.root[each.key].http_method
  integration_http_method = "POST"
  type        = "AWS_PROXY"
  uri         = aws_lambda_function.hello_lambda[each.key].invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  for_each      = aws_api_gateway_rest_api.api
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_lambda[each.key].function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api[each.key].execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deployment" {
  for_each    = aws_api_gateway_rest_api.api
  rest_api_id = each.value.id

   # Add explicit dependencies
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_method.root
  ]

   # Add triggers to force new deployment when integration or methods change
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.root[each.key],
      aws_api_gateway_integration.lambda[each.key]
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  for_each    = aws_api_gateway_rest_api.api
  deployment_id = aws_api_gateway_deployment.deployment[each.key].id
  rest_api_id = aws_api_gateway_rest_api.api[each.key].id
  stage_name  = "prod"
}

output "api_endpoints" {
  value = {
    for key, _ in local.apis : key => "https://${aws_api_gateway_rest_api.api[key].id}.execute-api.us-east-1.amazonaws.com/prod/"
  }
}
