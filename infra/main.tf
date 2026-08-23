terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

resource "aws_lambda_function" "tf-gha-test" {
  function_name = "tf-gha-test"
  role          = "arn:aws:iam::050478186852:role/service-role/tf-gha-test-role-iv4rs4b1"
  filename      = "../layer.zip"
  handler       = "index.handler"
  runtime       = "nodejs24.x"
  layers = [
    "arn:aws:lambda:ap-northeast-1:050478186852:layer:tf-gha-test-layer:3",
  ]
}
