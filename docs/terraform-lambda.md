# TerraformでLambdaを扱う


terraform import時点で必要になった権限
たぶんplanでも必要

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "lambda:GetLayerVersion",
                "lambda:ListVersionsByFunction",
                "lambda:GetFunction",
                "lambda:GetFunctionCodeSigningConfig"
            ],
            "Resource": "arn:aws:lambda:ap-northeast-1:050478186852:function:tf-gha-test"
        }
    ]
}
```

applyで必要になった権限

* lambda:UpdateFunctionCode