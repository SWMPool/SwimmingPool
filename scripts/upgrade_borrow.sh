#!/bin/bash

# rebuild borrow canister and forec upgrade it
dfx build borrow && dfx canister install borrow --mode upgrade --upgrade-unchanged --argument "
  (record {
    collateralToken = (principal \"$(dfx canister id collateral_token)\");
    stableToken = (principal \"$(dfx canister id stable_token)\");
  })
"