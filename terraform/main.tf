terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  required_version = ">= 1.6.0"
}

provider "aws" {
  region = var.aws_region
}

# Referencia IAM Role existente
data "aws_iam_role" "lambda_role" {
  name = "lambda_hola_mundo_role"
}

# Intentar usar Lambda existente
data "aws_lambda_function" "existing_lambda" {
  count         = 1
  function_name = "lambda_hola_mundo"
}

# Crear Lambda solo si no existe
resource "aws_lambda_function" "hola_mundo" {
  count             = length(data.aws_lambda_function.existing_lambda) == 0 ? 1 : 0
  function_name     = "lambda_hola_mundo"
  role              = data.aws_iam_role.lambda_role.arn
  handler           = "lambda_function.lambda_handler"
  runtime           = "python3.12"
  filename          = "${path.module}/hola.zip"
  source_code_hash  = filebase64sha256("${path.module}/hola.zip")
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "api" {
  name          = "lambda-hola-mundo-api"
  protocol_type = "HTTP"
}

# Integración Lambda → API Gateway
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                  = aws_apigatewayv2_api.api.id
  integration_type        = "AWS_PROXY"
  integration_uri         = length(data.aws_lambda_function.existing_lambda) > 0 ? data.aws_lambda_function.existing_lambda[0].arn : aws_lambda_function.hola_mundo[0].arn
  payload_format_version  = "2.0"
}

# Ruta GET /hello
resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Stage por default con auto deploy
resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

# Generar statement_id único para Lambda Permission
resource "random_id" "lambda_perm" {
  byte_length = 4
}

# Permisos para que API Gateway invoque Lambda
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowAPIGatewayInvoke-${random_id.lambda_perm.hex}"
  action        = "lambda:InvokeFunction"
  function_name = length(data.aws_lambda_function.existing_lambda) > 0 ? data.aws_lambda_function.existing_lambda[0].function_name : aws_lambda_function.hola_mundo[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# Output del endpoint
output "api_endpoint" {
  value = "${aws_apigatewayv2_stage.stage.invoke_url}hello"
}
