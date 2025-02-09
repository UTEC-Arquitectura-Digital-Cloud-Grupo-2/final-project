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
    "grupo2_lambda_1" = "lambda1"
    "grupo2_lambda_2" = "lambda2"
    "grupo2_lambda_3" = "lambda3"
  }
}

# Create zip files for Lambda functions
data "archive_file" "lambda_zip" {
  for_each    = local.apis
  type        = "zip"
  source_file = "../backend/${each.value}/lambda_hello.py"
  output_path = "../build/${each.value}.zip"
}


resource "aws_lambda_function" "hello_lambda" {
  for_each         = local.apis
  function_name    = each.key
  role             = data.aws_iam_role.lambda_role.arn
  runtime          = "python3.9"
  handler          = "lambda_hello.lambda_handler"
  filename         = data.archive_file.lambda_zip[each.key].output_path
  source_code_hash = data.archive_file.lambda_zip[each.key].output_base64sha256

  environment {
    variables = {
      API_NAME = each.key
    }
  }
}

# Create a single API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "grupo2_apigw"
}

# Create resources for each Lambda function
resource "aws_api_gateway_resource" "lambda_resource" {
  for_each    = local.apis
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = each.key
}

# Create methods for each resource
resource "aws_api_gateway_method" "root" {
  for_each      = local.apis
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.lambda_resource[each.key].id
  http_method   = "ANY"
  authorization = "NONE"
}

# Create integrations for each Lambda
resource "aws_api_gateway_integration" "lambda" {
  for_each                = local.apis
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.lambda_resource[each.key].id
  http_method             = aws_api_gateway_method.root[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello_lambda[each.key].invoke_arn
}

# Update Lambda permissions
resource "aws_lambda_permission" "apigw" {
  for_each      = local.apis
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_lambda[each.key].function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/${aws_api_gateway_method.root[each.key].http_method}/${each.key}"
}

# Single deployment
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

   # Add explicit dependencies
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_method.root,
    aws_api_gateway_resource.lambda_resource
  ]

   # Add triggers to force new deployment when integration or methods change
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.lambda_resource,
      aws_api_gateway_method.root,
      aws_api_gateway_integration.lambda
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Single stage
resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id  = aws_api_gateway_rest_api.api.id
  stage_name   = "prod"
}

output "api_endpoints" {
  value = {
    for key, _ in local.apis : key => "https://${aws_api_gateway_rest_api.api.id}.execute-api.us-east-1.amazonaws.com/prod/${key}"
  }
}
