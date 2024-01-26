
/// DEPLOY
```
dfx deploy collateral_token --upgrade-unchanged --argument '
 (variant {
    Init = record {
      token_name = "Token A";
      token_symbol = "A";
      minting_account = record {
        owner = principal "'${OWNER}'";
      };
      initial_balances = vec {
        record {
          record {
            owner = principal "'${USER}'";
          };
          100_000_000_000;
        };
      };
      metadata = vec {};
      transfer_fee = 10_000;
      archive_options = record {
        trigger_threshold = 2000;
        num_blocks_to_archive = 1000;
        controller_id = principal "'${OWNER}'";
      };
      feature_flags = opt record {
        icrc2 = true;
      };
    }
  })
'
```

```
dfx canister create borrow
```

```
dfx deploy stable_token --upgrade-unchanged --argument '
 (variant {
    Init = record {
      token_name = "Token A";
      token_symbol = "A";
      minting_account = record {
        owner = principal "'${BORROW_CANISTER_ID}'";
      };
      initial_balances = vec {};
      metadata = vec {};
      transfer_fee = 10_000;
      archive_options = record {
        trigger_threshold = 2000;
        num_blocks_to_archive = 1000;
        controller_id = principal "'${OWNER}'";
      };
      feature_flags = opt record {
        icrc2 = true;
      };
    }
  })
'
```

```
dfx deploy borrow --upgrade-unchanged --argument '(
  record {
    coll_token = (principal "'${COLLATERAL_TOKE_CANISTER_ID}'");
    stable_token = (principal "'${STABLE_TOKE_CANISTER_ID}'");
  }
)'
```

/// CALLS
```
dfx canister call collateral_token icrc2_approve '(record {
    spender = record { owner = principal "'${BORROW_CANISTER_ID}'" };
    amount = 1_000_000;
  })' --identity <SOME_IDENTITY>
```

```
dfx canister call borrow deposit '(record {
    amount = 100_000;
  })' --identity <SOME_IDENTITY>
```

```
dfx canister call stable_token icrc2_approve '(record {
    spender = record { owner = principal "'${BORROW_CANISTER_ID}'" };
    amount = 1_000_000;
  })' --identity <SOME_IDENTITY>
```

```
dfx canister call borrow withdraw '(record {
    amount = 90_000;
  })' --identity <SOME_IDENTITY>
```
