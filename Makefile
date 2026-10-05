# Offline checks: need only Terraform installed, no cloud accounts or credentials.
STACKS := snowflake redshift

.PHONY: check fmt init validate test clean

check: fmt validate test ## Run every offline check (default)

fmt: ## Check Terraform formatting
	terraform fmt -check -recursive

init: ## Download providers and modules (no backend, no state)
	@for s in $(STACKS); do terraform -chdir=$$s init -backend=false -input=false >/dev/null || exit 1; done

validate: init ## Validate both stacks
	@for s in $(STACKS); do echo "--- $$s"; terraform -chdir=$$s validate || exit 1; done

test: init ## Run the mocked test suite for every supported combination
	@for s in $(STACKS); do echo "--- $$s"; terraform -chdir=$$s test || exit 1; done

clean: ## Remove downloaded providers/modules
	rm -rf $(addsuffix /.terraform,$(STACKS))
