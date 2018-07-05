ENVIRONMENT=staging
REGION=us-east-1
BUCKET=tdc-terraform

init: ## Initializes the terraform remote state backend and pulls the correct environments state.
	@rm -rf .terraform
	@terraform init
	@-aws s3 cp s3://$(BUCKET)/$(ENVIRONMENT)/terraform.tfvars . --quiet
	@-aws s3 cp s3://$(BUCKET)/$(ENVIRONMENT)/key_pair_$(ENVIRONMENT) . --quiet

update: ## Gets any module updates
	@terraform get -update=true

apply: print_current_env update
	@terraform apply -input=false -auto-approve
	@aws s3 cp terraform.tfvars s3://$(BUCKET)/$(ENVIRONMENT)/terraform.tfvars
	@aws s3 cp key_pair_$(ENVIRONMENT) s3://$(BUCKET)/$(ENVIRONMENT)/key_pair_$(ENVIRONMENT)

plan: print_current_env update
	@terraform plan -input=false -refresh=true -module-depth=-1

output: print_current_env
	@terraform output

destroy: print_current_env update
	@terraform destroy -input=false -refresh=true -auto-approve

print_current_env:
	@echo "\033[1mYou current environment is $(ENVIRONMENT)\033[0m \n"
