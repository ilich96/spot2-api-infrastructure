package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"

	"github.com/stretchr/testify/assert"
)

func TestInfrastructure(t *testing.T) {
	t.Parallel()

	expectedElasticContainerRepositoryName := "ecr-test"
	expectedElasticContainerServiceClusterName := "ecs-cluster-test"

	// Pick a random AWS region to test in. This helps ensure your code works in all regions.
	awsRegion := aws.GetRandomStableRegion(t, []string{"us-east-1", "eu-west-1"}, nil)

	// Construct the terraform options with default retryable errors to handle the most common
	// retryable errors in terraform testing.
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Set the path to the Terraform code that will be tested.
		TerraformDir: "../",

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"ecr_name":         expectedElasticContainerRepositoryName,
			"ecs_cluster_name": expectedElasticContainerServiceClusterName,
			"region":           awsRegion,
		},
	})

	// Clean up resources with "terraform destroy" at the end of the test.
	defer terraform.Destroy(t, terraformOptions)

	// Run "terraform init" and "terraform apply". Fail the test if there are any errors.
	terraform.InitAndApply(t, terraformOptions)

	// Run `terraform output` to get the values of output variables and check they have the expected values.
	ecrName := terraform.Output(t, terraformOptions, "ecr_name")
	ecsClusterName := terraform.Output(t, terraformOptions, "ecs_cluster_name")
	assert.Equal(t, expectedElasticContainerRepositoryName, ecrName)
	assert.Equal(t, expectedElasticContainerServiceClusterName, ecsClusterName)
}
