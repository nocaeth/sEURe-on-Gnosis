install:
	curl -L https://foundry.paradigm.xyz | bash

tests:
	forge test -vvv

coverage:
	forge coverage --no-match-coverage "test/" --report summary --report lcov --report-file lcov.info

coverage-html: coverage
	genhtml lcov.info --output-directory coverage --branch-coverage --ignore-errors category

deploy-chiado:
	forge script script/SavingsEUReDeployer.s.sol --rpc-url chiado --broadcast

deploy-gnosis:
	forge script script/SavingsEUReDeployer.s.sol --rpc-url gnosis --broadcast --verify
