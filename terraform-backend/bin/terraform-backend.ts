#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { TfStateStack } from "../lib/tf-state-stack";

const app = new cdk.App();

new TfStateStack(app, "TfStateStack", {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
