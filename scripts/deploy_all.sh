#!/bin/bash

dfx deploy collateral_token --upgrade-unchanged --argument "
  (variant {
    Init = record {
      token_name = \"Collateral Token\";
      token_symbol = \"CT\";
      minting_account = record {
        owner = principal \"$OWNER_PRINCIPAL\";
      };
      initial_balances = vec {
        record {
          record {
            owner = principal \"$USER_PRINCIPAL\";
          };
          100_000_000_000;
        };
      };
      metadata = vec {};
      transfer_fee = 10_000;
      archive_options = record {
        trigger_threshold = 2000;
        num_blocks_to_archive = 1000;
        controller_id = principal \"$OWNER_PRINCIPAL\";
      };
      feature_flags = opt record {
        icrc2 = true;
      };
    }
  })
"

dfx canister create borrow

dfx deploy stable_token --upgrade-unchanged --argument "
 (variant {
    Init = record {
      token_name = \"Stable Token\";
      token_symbol = \"ST\";
      minting_account = record {
        owner = principal \"$(dfx canister id borrow)\";
      };
      initial_balances = vec {};
      metadata = vec {};
      transfer_fee = 10_000;
      archive_options = record {
        trigger_threshold = 2000;
        num_blocks_to_archive = 1000;
        controller_id = principal \"$OWNER_PRINCIPAL\";
      };
      feature_flags = opt record {
        icrc2 = true;
      };
    }
  })
"

dfx deploy borrow --upgrade-unchanged --argument "(
  record {
    collateralToken = (principal \"$(dfx canister id collateral_token)\");
    stableToken = (principal \"$(dfx canister id stable_token)\");
  }
)"