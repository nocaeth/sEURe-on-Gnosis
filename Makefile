install:
	curl -L https://foundry.paradigm.xyz | bash

tests:
	forge test -vvv

deploy-chiado:
	forge script script/SavingsEUReDeployer.s.sol --rpc-url chiado --broadcast

deploy-gnosis:
	forge script script/SavingsEUReDeployer.s.sol --rpc-url gnosis --broadcast --verify
