terraform {
  source = "./"
}

lambda_layers = [
  "arn:aws:lambda:ap-northeast-1:050478186852:layer:tf-gha-test-layer:3",
]