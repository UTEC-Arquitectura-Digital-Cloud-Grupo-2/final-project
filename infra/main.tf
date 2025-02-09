provider "aws" {
  region = "us-east-1"  # Change to your preferred region
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# IAM Policy for Logging
resource "aws_iam_policy_attachment" "lambda_logs" {
  name       = "lambda_logs"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create 3 Lambda functions with API Gateway
locals {
  apis = ["api1", "api2", "api3"]
}

resource "aws_lambda_function" "hello_lambda" {
  for_each      = toset(local.apis)
  function_name = each.value
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.9"
  handler       = "lambda_hello.lambda_handler"
  filename      = "${path.module}/lambda_hello.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_hello.zip")

  environment {
    variables = {
      API_NAME = each.value
    }
  }
}

resource "aws_api_gateway_rest_api" "api" {
  for_each = toset(local.apis)
  name     = "${each.value}_api"
}

resource "aws_api_gateway_resource" "proxy" {
  for_each    = aws_api_gateway_rest_api.api
  rest_api_id = each.value.id
  parent_id   = each.value.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  for_each      = aws_api_gateway_rest_api.api
  rest_api_id   = each.value.id
  resource_id   = aws_api_gateway_resource.proxy[each.key].id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  for_each    = aws_api_gateway_rest_api.api
  rest_api_id = each.value.id
  resource_id = aws_api_gateway_resource.proxy[each.key].id
  http_method = aws_api_gateway_method.proxy[each.key].http_method
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
  stage_name  = "prod"
}

output "api_endpoints" {
  value = {
    for api in local.apis : api => "https://${aws_api_gateway_rest_api.api[api].id}.execute-api.${var.aws_region}.amazonaws.com/prod/"
  }
}
