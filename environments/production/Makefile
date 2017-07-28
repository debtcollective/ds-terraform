ENVIRONMENT=production
REGION=us-west-2
BUCKET=debtcollective-terraform

init: ## Initializes the terraform remote state backend and pulls the correct environments state.
	@rm -rf .terraform/*.tf*
	@terraform init
	@-aws s3 cp s3://$(BUCKET)/$(ENVIRONMENT)/terraform.tfvars . --quiet
	@aws s3 cp s3://$(BUCKET)/$(ENVIRONMENT)/files/config.js ./files/config.js --quiet
	@aws s3 cp s3://$(BUCKET)/$(ENVIRONMENT)/files/id_rsa ./files/id_rsa --quiet

config-pull:
	@aws s3 cp s3://$(BUCKET)/$(ENVIRONMENT)/files/config.js ./files/config.js
	@aws s3 cp s3://$(BUCKET)/$(ENVIRONMENT)/files/id_rsa ./files/id_rsa

tfvars-pull:
	@aws s3 cp s3://$(BUCKET)/$(ENVIRONMENT)/terraform.tfvars .

update: ## Gets any module updates
	@terraform get -update=true

apply: print_current_env update
	@terraform apply -input=false -refresh=true
	@aws s3 cp terraform.tfvars s3://$(BUCKET)/$(ENVIRONMENT)/terraform.tfvars

plan: print_current_env update
	@terraform plan -input=false -refresh=true -module-depth=-1

output: print_current_env
	@terraform output

destroy: print_current_env remote-pull update
	@terraform destroy -input=false -refresh=true

print_current_env:
	@echo "\033[1mYou current environment is $(ENVIRONMENT)\033[0m \n"
