terraform {
  source = "./"
}

lambda_layers = [
  "arn:aws:lambda:ap-northeast-1:000000000000:layer:tf-gha-test-layer:1",
]